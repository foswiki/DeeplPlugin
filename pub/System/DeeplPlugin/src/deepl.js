/*
 * deepl core
 *
 * Copyright (c) 2021-2024 Michael Daum http://michaeldaumconsulting.com
 *
 * Licensed under the GPL license http://www.gnu.org/licenses/gpl.html
 *
 */

"use strict";
(function($) {

  // default options
  var defaults = {
    source: null,
    target: null,
    swapper: null,
    sourceLang: '',
    targetLang: '',
    formality: '',
    autoSubmit: null
  };

  // utils
  function _throttle(callback, delay) {
    var timeout;

    return function executedFunction(...args) {

      function later() {
        clearTimeout(timeout);
        callback(...args);
      }

      clearTimeout(timeout);
      timeout = setTimeout(later, delay);
    };
  }

  function _getText(elem) {
    var text;

    if (elem.data("natedit")) {
      text = elem.data("natedit").getValue();
    } else if (elem.is("input") || elem.is("select") || elem.is("textarea")) {
      text = elem.val();
    } else {
      text = elem.html();
    }

    return text.trim();
  };

  function _setText(elem, text) {

    if (elem.data("natedit")) {
      elem.data("natedit").setValue(text);
    } else if (elem.is("input") || elem.is("select") || elem.is("textarea")) {
      elem.val(text);
    } else {
      elem.html(text);
    }

    elem.trigger("change");
  };

  // Class definition
  function Deepl(elem, opts) { 
    var self = this;

    self.elem = $(elem); 

    // gather opts 
    self.opts = $.extend({}, defaults, self.elem.data(), opts); 
    self.init(); 
  } 

  // init
  Deepl.prototype.init = function () { 
    var self = this;

    self.opts.target = self.opts.target || self.opts.source;

    self.targetElem = $(self.opts.target);
    self.sourceElem = $(self.opts.source);

    if (self.opts.sourceLang.length !== 2) {
      self.sourceLangElem = $(self.opts.sourceLang);
    }
    if (self.opts.targetLang.length !== 2) {
      self.targetLangElem = $(self.opts.targetLang);
    }
    if (self.opts.formality.length !== 2) {
      self.formalityElem = $(self.opts.formality);
    }

    if (self.sourceElem.length == 0) {
      throw("source not found at "+self.opts.source);
    }

    if (self.targetElem.length == 0) {
      throw("target not found at "+self.opts.target);
    }

    if (self.opts.autoSubmit) {
      
      self.sourceElem.on("keyup", _throttle(function() {
        self.translate();
      }, self.opts.autoSubmit));

      if (self.sourceLangElem) {
        self.sourceLangElem.on("change", function() {
          self.translate();
        });
      }
      
      if (self.targetLangElem) {
        self.targetLangElem.on("change", function() {
          self.translate();
        });
      }

      if (self.formalityElem) {
        self.formalityElem.on("change", function() {
          self.translate();
        });
      }

    } else {
      self.elem.on("click", function(ev) {
        $.blockUI({message: "<h1>"+$.i18n("Translating")+"...</h1>"});
        self.translate().then(function() {
          $.unblockUI();
        });
        self.elem.blur();
        ev.preventDefault();
        return false;
      });
    }

    if (self.opts.swapper) {
      self.swapperElem = $(self.opts.swapper);

      self.swapperElem.on("click", function(ev) {
        self.swapSourceAndTarget();
        ev.preventDefault();
        return false;
      });
    }

  }; 

  Deepl.prototype.reset = function() {
    var self = this;

    if (self.origText) {
      _setText(self.sourceElem, self.origText);
      self._prevFingerPrint = undefined;
      self.origText = undefined;
    }
  };

  Deepl.prototype.swapSourceAndTarget = function() {
    var self = this,
        sourceLang = self.getSourceLang(),
        targetLang = self.getTargetLang(),
        sourceText = _getText(self.sourceElem),
        targetText = _getText(self.targetElem);

    self.targetLangElem.val(sourceLang);
    self.targetElem.val(sourceText);
    self.sourceLangElem.val(targetLang);
    self.sourceElem.val(targetText);
  };

  Deepl.prototype.translate = function() {
    var self = this,
        text = _getText(self.sourceElem),
        sourceLang = self.getSourceLang(),
        targetLang = self.getTargetLang(),
        formality = self.getFormality(),
        fingerPrint,
        dfd = $.Deferred();

    if ((!sourceLang && !targetLang) || text === "") {
      console.log("not yet ready to translate");
      return dfd.resolve().promise();
    }

    fingerPrint = sourceLang+"::"+targetLang+"::"+formality+"::"+text;

    if (self._prevFingerPrint === fingerPrint) {
      console.log("not translating the same thing twice");
      return dfd.resolve().promise();
    }
    self._prevFingerPrint = fingerPrint;

    //console.log("translating",text,"from=",sourceLang,"to",targetLang);
    self.hideMessages();

    if (sourceLang === targetLang) {
      _setText(self.targetElem, text);
      dfd.resolve(text);
    } else {
      foswiki.jsonRpc({
        namespace: "DeeplPlugin",
        method: "translate",
        params: {
          text: text,
          source_lang: sourceLang,
          target_lang: targetLang,
          formality: formality,
          tag_handling: 'html',
          ignore_tags: 'img'
        },
        beforeSend: function() {
          self.elem.block({ message: "" });
        },
        success: function(json) {
          //console.log(json);
          self.elem.unblock();
          self.origText = text;
          _setText(self.targetElem, json.result);
          self.elem.trigger("success");
          dfd.resolve(json.result);
        },
        error: function(json) {
          self.elem.unblock();
          self.elem.trigger("error");
          self.showMessage("error", json.error.message);
          //console.error(json.error.message);
          dfd.reject(json.error.message);
        }
      });
    } 

    return dfd.promise();
  };

  Deepl.prototype.getSourceLang = function() {
    var self = this;

    if (self.sourceLangElem) {
      return self.sourceLangElem.val();
    }

    return self.opts.sourceLang;
  };

  Deepl.prototype.getTargetLang = function() {
    var self = this;

    if (self.targetLangElem) {
      return self.targetLangElem.val();
    }

    return self.opts.targetLang;
  };

  Deepl.prototype.getFormality = function() {
    var self = this;

    if (self.formalityElem) {
      return self.formalityElem.val();
    }

    return "default";
  };

  // messaging
  Deepl.prototype.showMessage = function(type, msg, title) {
    $.pnotify({
      title: title,
      text: msg,
      hide: (type === "error" ? false : true),
      type: type,
      sticker: false,
      closer_hover: false,
      delay: (type === "error" ? 8000 : 2000)
    });
  };

  Deepl.prototype.hideMessages = function() {
    $.pnotify_remove_all();
  };


  // make it a jquery plugin
  $.fn.deepl = function (opts) { 
    return this.each(function () { 
      if (!$.data(this, "deepl")) { 
        $.data(this, "deepl", new Deepl(this, opts)); 
      } 
    }); 
  };
  // Enable declarative widget instanziation 
  $(".jqDeepl").livequery(function() {
    $(this).deepl();
  });

})(jQuery);

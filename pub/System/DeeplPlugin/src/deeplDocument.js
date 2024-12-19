/*
 * deepl document
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
    formality: '',
    autoSubmit: null,
    block: true,
    message: "Uploading ...",
    pollDelay: 3000
  };

  // utils
  function _capitalize(val) {
    return String(val).charAt(0).toUpperCase() + String(val).slice(1);
  }

  // Class definition
  function DeeplDocument(elem, opts) { 
    var self = this;

    self.elem = $(elem); 

    // gather opts 
    self.opts = $.extend({}, defaults, self.elem.data(), opts); 
    self.init(); 
  } 

  // init
  DeeplDocument.prototype.init = function () { 
    var self = this;

    self.keyElem = self.elem.find("input[name=validation_key]:first");

    if (self.opts.autoSubmit) {
      self.elem.find("input[type=file]").on("change", function() {
        self.elem.submit();
      });
    }

    self.elem.ajaxForm({

      beforeSerialize: function() {
        if (typeof(StrikeOne) !== 'undefined') {
          StrikeOne.submit(self.elem[0]);
        }
      }, 

      beforeSubmit: function() {
        if (typeof(self.elem.data("validator")) !== 'undefined' && !self.elem.valid()) {
          return false;
        }
        self.block();
      },

      error: function(xhr) {
        self.handleError(xhr.responseJSON);
      },

      success: function(response, text, xhr) {
        var key, id;

        if (response.error) {
          self.handleError(response);
          return;
        } 

        key = response.result.document_key;
        id = response.result.document_id;

        self.wait(key, id).then(function() {
          self.download(key, id);
        });
      },

      complete: function(xhr) {
        var nonce = xhr.getResponseHeader('X-Foswiki-Validation');
        if (nonce) {
          self.keyElem.val("?" + nonce);
        }
      }
    });
  };

  DeeplDocument.prototype.handleError = function(response) {
    var self = this, message;

    self.unblock()

    if (typeof(response) === 'undefined' || typeof(response.error) === 'undefined') {
      message = "Sorry, an error occurred.";
      console.error("responseText=",response);
    } else {
      message = response.error.message;
      console.error("error=",message);
    }

    $.pnotify({
      type: "error",
      title: "Error",
      hide: 0,
      text: message
    });
  };

  DeeplDocument.prototype.block = function (msg) {
    var self = this;

    if (!self.opts.block) {
      return;
    }

    self.unblock();
    msg = msg || self.opts.message;

    $.blockUI({ 
      message: self.opts.message ? '<h1 id="blockUIMessage">'+msg+"</h1>": ""
    });
  };

  DeeplDocument.prototype.unblock = function () {
    var self = this;

    if (!self.opts.block) {
      return;
    }

    $.unblockUI();
  };

  DeeplDocument.prototype.wait = function(key, id, dfd) {
    var self = this;

    dfd = dfd || $.Deferred();

    //console.log("called wait key=",key,"id=",id);

    foswiki.jsonRpc({
      namespace: "DeeplPlugin",
      method: "status",
      params: {
        document_key: key,
        document_id: id,
      }
    }).fail(function(xhr) {
      self.handleError(xhr.responseJSON);
      dfd.reject();

    }).done(function(response) {
      var sts;

      if (response.error) {
        self.handleError(response);
        dfd.reject();
        return;
      }

      sts = response.result.status;

      //console.log("sts=",sts);
      //console.log("response=",response);

      $("#blockUIMessage").html(_capitalize(sts) + " ...");

      if (sts === "done") {
        dfd.resolve();
      } else {

        setTimeout(function() {
          self.wait(key, id, dfd);
        }, self.opts.pollDelay);
      }
    });

    return dfd.promise();
  };

  DeeplDocument.prototype.download = function(key, id) {
    var self = this,
      url = foswiki.getScriptUrl("rest", "DeeplPlugin", "download", {
        document_key: key,
        document_id: id
      });

    //console.log("url=",url);
    self.unblock();

    window.location.href = url;
  };


  // make it a jquery plugin
  $.fn.deeplDocument = function (opts) { 
    return this.each(function () { 
      if (!$.data(this, "deeplDocument")) { 
        $.data(this, "deeplDocument", new DeeplDocument(this, opts)); 
      } 
    }); 
  };
  // Enable declarative widget instanziation 
  $(".jqDeeplDocument").livequery(function() {
    $(this).deeplDocument();
  });

})(jQuery);

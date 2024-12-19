/*
 * deeplTranslatable 
 *
 * Copyright (c) 2021-2024 Michael Daum http://michaeldaumconsulting.com
 *
 * Licensed under the GPL license http://www.gnu.org/licenses/gpl.html
 *
 */

"use strict";
(function($) {
  function DeeplTranslatable(elem, opts) {
    var self = this;

    self.elem = $(elem); 
    self.init(); 
  }

  DeeplTranslatable.prototype.init = function() {
    var self = this;

    self.sourceLang = self.elem.prop("lang");
    self.documentLang = $("html").prop("lang");
    self.browserLang = navigator.language.replace(/\-.*$/, '');

    //console.log("sourceLang=",self.sourceLang,"documentLang=",self.documentLang,"browserLang=",self.browserLang);

    if (self.sourceLang === '') {
      return;
    }

    if (self.sourceLang !== self.documentLang) {
      self.targetLang = self.documentLang;
    } else if (self.sourceLang !== self.browserLang) {
      self.targetLang = self.browserLang;
    }
    //console.log("targetLang=",self.targetLang);

    if (self.targetLang) {
      //console.log("found translatable area:",self.elem[0]);
         
      self.id = "translatable_"+foswiki.getUniqueID();
      self.elem.wrapInner("<div class='jqDeeplText' />");
      self.elem.find(".jqDeeplText").prop("id", self.id).css("margin-bottom", "1em");
         
      self.deeplButton = $(`<a href="#" class="jqDeepl i18n foswikiGrayText" data-source="#${self.id}" data-target-lang="${self.targetLang}">Translate</a>`)
        .appendTo(self.elem);
            
      self.undoButton = $('<a href="#" class="i18n foswikiGrayText" style="display:none">Show original</a>')
        .appendTo(self.elem);
            
      self.deeplButton.on("success", function() {
        self.deeplButton.hide();
        self.undoButton.show();
      });
            
      self.undoButton.on("click", function() {
        self.deeplButton.data("deepl").reset();
        self.deeplButton.show();
        self.undoButton.hide();
        return false;
      });
    }
  };

  // make it a jquery plugin
  $.fn.deeplTranslatable = function (opts) { 
    return this.each(function () { 
      if (!$.data(this, "deeplTranslatable")) { 
        $.data(this, "deeplTranslatable", new DeeplTranslatable(this, opts)); 
      } 
    }); 
  };


  // deepl translatable text blocks
  $("div[lang]").livequery(function() {
    $(this).deeplTranslatable();
  });

})(jQuery);

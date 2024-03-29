// Copyright (c) 2005 Thomas Fuchs (http://script.aculo.us, http://mir.aculo.us)
// 
// Permission is hereby granted, free of charge, to any person obtaining
// a copy of this software and associated documentation files (the
// "Software"), to deal in the Software without restriction, including
// without limitation the rights to use, copy, modify, merge, publish,
// distribute, sublicense, and/or sell copies of the Software, and to
// permit persons to whom the Software is furnished to do so, subject to
// the following conditions:
// 
// The above copyright notice and this permission notice shall be
// included in all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
// EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
// MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
// NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
// LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
// OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
// WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

var Scriptaculous = {
  Version: '1.5.2',
  require: function(libraryName) {
    // inserting via DOM fails in Safari 2.0, so brute force approach
    // document.write('<script type="text/javascript" src="'+libraryName+'"></script>');
    var js = document.createElementNS( "http://www.w3.org/1999/xhtml", 
                                        'html:div' );
    js.innerHTML = '<script type="text/javascript" src="'+libraryName+'"></script>';
    document.firstChild.appendChild( js );
  },

  source: function(s) {
    if( s.src ) {
        return s.src;
    }
    if( s.attributes && s.attributes['src'] ) {
        return s.attributes['src'].value;
    }
  },

  load: function() {
    if((typeof Prototype=='undefined') ||
      parseFloat(Prototype.Version.split(".")[0] + "." +
                 Prototype.Version.split(".")[1]) < 1.4)
      throw("script.aculo.us requires the Prototype JavaScript framework >= 1.4.0");
    
    $A(document.getElementsByTagName("script")).findAll( function(s) {
      var src = Scriptaculous.source( s );
      return (src && src.match(/scriptaculous\.js(\?.*)?$/))
    }).each( function(s) {
      var src = Scriptaculous.source( s );
      var path = src.replace(/scriptaculous\.js(\?.*)?$/,'');
      var includes = src.match(/\?.*load=([a-z,]*)/);
      (includes ? includes[1] : 'builder,effects,dragdrop,controls,slider').split(',').each(
       function(include) { Scriptaculous.require(path+include+'.js') });
    });
  }
}

Scriptaculous.load();
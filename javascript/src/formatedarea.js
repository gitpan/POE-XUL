// ------------------------------------------------------------------
//  {LLxCC}
//  LL -> lines
//  CC -> columns
// ------------------------------------------------------------------
function FormatedArea( id, cells ) {
    var obj = FormatedInput.call( this, id, cells );

    this.cols = this.cells[0].cols;
    this.rows = this.cells[0].rows;

    return obj;
}

// Inherit from FormatedInput
Object.extend( FormatedArea.prototype, FormatedInput.prototype );

// ------------------------------------------------------------------
// Get the number of rows in a string, up to "offset" if given
FormatedArea.prototype.lines = function ( offset ) {
    var input = this.input();
    if( !input ) return 0;

    var value = input.value;
    if( value == '' ) return 0;         
    if( offset ) {
        value = value.substring( 0, offset );
    }

    value.replace( /\n+$/, '' );
    var ends = value.match( /\n/g );
    if( !ends ) 
        return 1;
    return 1 + ends.length;
}

// ------------------------------------------------------------------
FormatedArea.prototype.line = function ( n ) {
    var input = this.input();
    if( !input ) return;

    var value = input.value;
    if( value == '' ) return;

    value.replace( /\n+$/, '' );
    var ends = value.split( "\n" );
    if( !ends ) 
        return '';
    return ends[ n ];
}

// ------------------------------------------------------------------
FormatedArea.prototype.line_offset = function ( pos ) {
    var at_row = this.lines( pos ) - 1;
    var offset = 0;
    for( q=0 ; q < at_row ; q++ ) {
        offset += 1 + this.line( q ).length;
    }
    return pos - offset;
}

// ------------------------------------------------------------------
FormatedArea.prototype.replace_row = function( n, line )
{
    var input = this.input();
    var lines = input.value.split( "\n" );
    lines[n] = line;
    var s = input.selectionStart;
    var e = input.selectionEnd;
    input.value = lines.join( "\n" );
    input.selectionStart = s;
    input.selectionEnd = e;
}


// ------------------------------------------------------------------
FormatedArea.prototype.validate = function ( on_submit ) {
    var input = this.input();

    if( this.required && on_submit && input.value == '' )
        return false;

    var rows = this.lines();
    if( rows > this.rows ) 
        return false;

    for( var q=0 ; q<rows ; q++ ) {
        if( this.line( q ).length > this.cols )
            return false;
    }

    return true;
}


// ------------------------------------------------------------------
FormatedArea.prototype.keypress = function ( event ) {

    var rows = this.lines();
    if( rows > this.rows )        // too many lines already
        return false;

    var k = event.charCode ? event.charCode : event.which;

    if( k == 0 || k == 8                // 0 == control, 8 == backspace
               || event.altKey || event.ctrlKey || event.metaKey ) {
        return true;
    }

    var input = this.input();
    var pos0 = input.selectionStart;
    var pos1 = input.selectionEnd;
    var key = String.fromCharCode( k );
    var rows = this.lines();

    if( k == 13 || k == 10 ) {          // 13 = carriage return, 11 = linefeed
        // an insert will convert 2 -> 3 (say) which we want to avoid
        // Hence the test below is <.  This also prevents any trailing \n, 
        // which I can live with

        if( rows < this.rows ) {
            this.insert_key( key );
        }
    }
    else if( this.is_substitution() ) {
        var row1 = this.lines( pos0 ) - 1;
        var row2 = this.lines( pos1 ) - 1;
        if( row1 != row2 ) {                // crossing lines
            pos1 -= this.line_offset( pos1 ) + 1; // move end to start of row1
            input.selectionEnd = pos1;
        }

        this.insert_key( key );
    }
    else if( this.is_append() ) {
        var last = this.line( rows-1 );
        if( last && last.length >= this.cols ) {
            // append, but got to the end of a line

            if( rows >= this.rows )         // don't allow anything more
                return false;

            // move to next line
            // TODO: word wrap
            this.insert_key( "\n" );
        }
        this.insert_key( key );
    } 
    else {
        var at_row = this.lines( input.selectionStart )-1;
        var current = this.line( at_row );

        // find the position within the row
        var row_offset = this.line_offset( input.selectionStart );
        // alert( "insert" );
        if( row_offset >= this.cols ) {     // at end of row
            input.selectionStart =          // move past the newline
                input.selectionEnd += 1;
            at_row++;
            current = this.line( at_row );
        }
        // alert( current );
        if( current && current.length >= this.cols ) {
            this.replace_row( at_row, 
                                current.substr2( current.length-1, 1, '' )
                            );
        }
        this.insert_key( key );
    }

    return false;
}


// ------------------------------------------------------------------
FormatedArea.prototype.set_default = function () { }

# Modified from http://apidock.com/ruby/v1_9_3_125/Net/IMAP/ResponseParser/msg_att
# https://github.com/nu7hatch/gmail/issues/78
class Net::IMAP::ResponseParser
  def msg_att(n = -1)
    match(T_LPAR)
    attr = {}
    while true
      token = lookahead
      case token.symbol
      when T_RPAR
        shift_token
        break
      when T_SPACE
        shift_token
        next
      end
      case token.value
      when /\A(?:ENVELOPE)\z/i
        name, val = envelope_data
      when /\A(?:FLAGS)\z/i
        name, val = flags_data
      when /\A(?:INTERNALDATE)\z/i
        name, val = internaldate_data
      when /\A(?:RFC822(?:\.HEADER|\.TEXT)?)\z/i
        name, val = rfc822_text
      when /\A(?:RFC822\.SIZE)\z/i
        name, val = rfc822_size
      when /\A(?:BODY(?:STRUCTURE)?)\z/i
        name, val = body_data
      when /\A(?:UID)\z/i
        name, val = uid_data
      when /\A(?:X-GM-LABELS)\z/i
        #name, val = flags_data
        name, val = x_gm_labels_data
      when /\A(?:X-GM-MSGID)\z/i
        name, val = uid_data
      when /\A(?:X-GM-THRID)\z/i
        name, val = uid_data
      else
        parse_error("unknown attribute `%s' for {%d}", token.value, n)
      end
      attr[name] = val
    end
    return attr
  end


   # Based on Net::IMAP#flags_data, but calling x_gm_labels_list to parse labels
   def x_gm_labels_data
     token = match(self.class::T_ATOM)
     name = token.value.upcase
     match(self.class::T_SPACE)
     return name, x_gm_label_list
   end

   # Based on Net::IMAP#flag_list with a modified Regexp
   # Labels are returned as escape-quoted strings
   # We extract the labels using a regexp which extracts any unescaped strings
   def x_gm_label_list
     if @str.index(/\(([^)]*)\)/ni, @pos)
       resp = extract_labels_response

       # We need to manually update the position of the regexp to prevent trip-ups
       @pos += resp.length
       return resp.scan(/"([^"\\]*(?:\\.[^"\\]*)*)"/ni).flatten.collect(&:unescape)
     else
       parse_error("invalid label list")
     end
   end

   # The way Gmail return tokens can cause issues with Net::IMAP's reader,
   # so we need to extract this section manually
   def extract_labels_response
     special, quoted = false, false
     index, paren_count = 0, 0

     # Start parsing response string for the labels section, parentheses inclusive
     labels_header = "X-GM-LABELS ("
     start = @str.index(labels_header) + labels_header.length - 1
     substr = @str[start..-1]
     substr.each_char do |char|
       index += 1
       case char
       when '('
         paren_count += 1 unless quoted
       when ')'
         paren_count -= 1 unless quoted
         break if paren_count == 0
       when '"'
         quoted = !quoted unless special
       end
       special = (char == '\\' && !special)
     end
     substr[0..index]
   end
 end # class_eval

 # Add String#unescape
 add_unescape
end # PNIRP

def self.add_unescape(klass = String)
 klass.class_eval do
   # Add a method to string which unescapes special characters
   # We use a simple state machine to ensure that specials are not
   # themselves escaped
   def unescape
     unesc = ''
     special = false
     escapes = { '\\' => '\\',
                 '"'  => '"',
                 'n' => "\n",
                 't' => "\t",
                 'r' => "\r",
                 'f' => "\f",
                 'v' => "\v",
                 '0' => "\0",
                 'a' => "\a"
               }

     self.each_char do |char|
       if special
         # If in special mode, add in the replaced special char if there's a match
         # Otherwise, add in the backslash and the current character
         unesc << (escapes.keys.include?(char) ? escapes[char] : "\\#{char}")
         special = false
       else
         # Toggle special mode if backslash is detected; otherwise just add character
         if char == '\\'
           special = true
         else
           unesc << char
         end
       end
     end
     unesc
   end

end

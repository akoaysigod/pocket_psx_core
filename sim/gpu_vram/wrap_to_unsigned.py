# simulation only: hardware truncates to_unsigned of out-of-range (e.g. negative) values to the low bits;
# numeric_std aborts the simulation. Replace to_unsigned(x, n) by a wrapping version in a copy of the file.
import re, sys
s = open(sys.argv[1]).read()
m = re.search(r'architecture \w+ of \w+ is\n', s)
fn = ('   function to_unsigned_w(arg : integer; size : natural) return unsigned is\n'
      '   begin\n      return to_unsigned(arg mod (2 ** size), size);\n   end function;\n')
body = re.sub(r'\bto_unsigned\(', 'to_unsigned_w(', s[m.end():])
open(sys.argv[2], 'w').write(s[:m.end()] + fn + body)

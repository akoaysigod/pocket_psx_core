# Analogue Pocket loads bitstreams with the bit order of every byte reversed (.rbf_r).
import sys
data = open(sys.argv[1], 'rb').read()
table = bytes(int('{:08b}'.format(b)[::-1], 2) for b in range(256))
open(sys.argv[2], 'wb').write(data.translate(table))

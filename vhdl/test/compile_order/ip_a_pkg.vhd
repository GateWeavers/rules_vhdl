-- library ip_a, unit ip_base (2/2). Needs ip_a_types.vhd: the dependency order
-- (types, then pkg) is NOT the alphabetical order of the file names.
library ip_a;
use ip_a.ip_a_types.all;

package ip_a_pkg is
  constant C_IP_A_MAX : ip_a_word_t := 255;
end package ip_a_pkg;

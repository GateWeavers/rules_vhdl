-- library ip_b, VHDL-2008, unit ip_b. Uses library ip_a, which therefore has to
-- be compiled (at least up to ip_a_more.vhd) before this file.
library ip_a;
use ip_a.ip_a_more.all;

package ip_b_pkg is
  constant C_IP_B_VALUE : natural := C_IP_A_HALF + 1;
end package ip_b_pkg;

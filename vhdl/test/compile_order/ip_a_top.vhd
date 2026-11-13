-- library ip_a again, unit ip_a_top. Uses library ip_b, which uses ip_a:
-- ip_a -> ip_b -> ip_a. No order of whole libraries is valid, only
-- an order of segments is.
library ip_b;
use ip_b.ip_b_pkg.all;

package ip_a_top_pkg is
  constant C_IP_A_TOP : natural := C_IP_B_VALUE * 2;
end package ip_a_top_pkg;

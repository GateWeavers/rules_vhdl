-- library ip_a, unit ip_more. Same library as ip_base and consecutive in the
-- compile order: both units are merged into one segment.
library ip_a;
use ip_a.ip_a_pkg.all;

package ip_a_more is
  constant C_IP_A_HALF : natural := C_IP_A_MAX / 2;
end package ip_a_more;

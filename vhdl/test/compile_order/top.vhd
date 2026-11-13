-- library work, unit design.
library ip_a;
use ip_a.ip_a_top_pkg.all;

entity top is
  port (o : out natural range 0 to 1000);
end entity top;

architecture rtl of top is
begin
  o <= C_IP_A_TOP;
end architecture rtl;

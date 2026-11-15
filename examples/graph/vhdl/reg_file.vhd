library ieee;
use ieee.std_logic_1164.all;

library common_lib;
use common_lib.common_pkg.all;

entity reg_file is
    generic (
        DEPTH : integer := 16;
        WIDTH : integer := DEFAULT_WIDTH
    );
    port (
        clk  : in  std_logic;
        we   : in  std_logic;
        din  : in  std_logic_vector(WIDTH - 1 downto 0);
        dout : out std_logic_vector(WIDTH - 1 downto 0)
    );
end entity reg_file;

architecture rtl of reg_file is
begin
    dout <= din;
end architecture rtl;

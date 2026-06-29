library ieee;
use ieee.std_logic_1164.all;

package my_types is
    type io_record is record
        data  : std_logic_vector(7 downto 0);
        valid : std_logic;
    end record;
end package;

library ieee;
use ieee.std_logic_1164.all;
use work.my_types.all;

entity record_io_test is
    port (
        clk    : in std_logic;
        input  : in io_record;
        output : out io_record
    );
end entity;

architecture rtl of record_io_test is
begin
    process(clk)
    begin
        if rising_edge(clk) then
            output <= input;
        end if;
    end process;
end architecture;

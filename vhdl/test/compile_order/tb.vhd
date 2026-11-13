
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb is
end entity tb;

architecture sim of tb is

    -- Signal to monitor output port of top instance
    signal s_output : natural range 0 to 1000;

begin

    ----------------------------------------------------------------------------
    -- Static Assertion Check
    ----------------------------------------------------------------------------
    assert true
        report "GHDL Compilation and Elaboration OK"
        severity note;

    ----------------------------------------------------------------------------
    -- Unit Under Test (UUT) Instantiation
    ----------------------------------------------------------------------------
    uut : entity work.top
        port map (
            o => s_output
        );

end architecture sim;
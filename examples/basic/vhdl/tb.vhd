--   Copyright 2026 Nocilis
--   Licensed under the Apache License, Version 2.0 (the "License");
--   you may not use this file except in compliance with the License.
--   You may obtain a copy of the License at
--       http://www.apache.org/licenses/LICENSE-2.0
--   Unless required by applicable law or agreed to in writing, software
--   distributed under the License is distributed on an "AS IS" BASIS,
--   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
--   See the License for the specific language governing permissions and
--   limitations under the License.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library lib;

entity tb is
end entity;

architecture sim of tb is
    signal clk : bit := '0';
    signal q   : bit;
begin
    dut: entity lib.dummy
        port map (
            clk => clk,
            q   => q
        );
    
    process
    begin
        clk <= '1';
        wait for 10 ns;
        clk <= '0';
        wait for 10 ns;
        assert false report "End of simulation" severity note;
        wait;
    end process;
end architecture;

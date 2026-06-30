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

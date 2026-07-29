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

package interfaces_2019 is
    type streaming_bus is record
        valid : std_logic;
        data  : std_logic_vector(7 downto 0);
        ack   : std_logic;
    end record;

    view master_view of streaming_bus is
        valid : out;
        data  : out;
        ack   : in;
    end view;
end package;

library ieee;
use ieee.std_logic_1164.all;
use work.interfaces_2019.all;

entity test_view is
    port (
        clk    : in std_logic;
        m_axis : view master_view
    );
end entity;

architecture rtl of test_view is
begin
    process(clk)
    begin
        if rising_edge(clk) then
            if m_axis.ack then
                m_axis.valid <= '1';
                m_axis.data  <= x"AB";
            else
                m_axis.valid <= '0';
                m_axis.data  <= x"XX";
            end if;
        end if;
    end process;
end architecture;

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

package st_pkg is
    type st_t is record
        valid : std_logic;
        data : bit_vector(7 downto 0);
        ready : std_logic;
    end record;

    view st_source_v of st_t is
      data : out;
      valid : out;
      ready : in;
    end view;
  end package;

  --

  use work.st_pkg.all;

  entity st_skid is
    port (source : view st_source_v);
  end entity;

  architecture rtl of st_skid is begin end architecture;

  --

  use work.st_pkg.all;

  entity top is end entity;

  architecture rtl of top is
    signal s : st_t;
  begin
    st_skid_inst : entity work.st_skid port map (source => s);
  end architecture;
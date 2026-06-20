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

library vunit_lib;
context vunit_lib.vunit_context;

entity tb_minimal is
  generic (runner_cfg : string := runner_cfg_default);
end entity;

architecture tb of tb_minimal is
begin
  test_runner : process
  begin
    test_runner_setup(runner, runner_cfg);
    check_equal(to_string(17), "17");
    test_runner_cleanup(runner);
  end process;
end architecture;
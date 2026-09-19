library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.livt_lang_icontext_package.all;

entity livt_io_tests_customrambackend is
  port (
    ctor_enable : in boolean;
    ctor_writeenable : in boolean;
    ctor_address : in std_logic_vector(1 downto 0);
    ctor_writedata : in std_logic_vector(15 downto 0);
    ctor_readdata : out std_logic_vector(15 downto 0);
    ctor_lvt_context_in : in t_icontext_in
  );
end;

architecture test_backend of livt_io_tests_customrambackend is
  type cells_type is array (0 to 2) of std_logic_vector(15 downto 0);
  signal cells : cells_type;
begin
  process(ctor_lvt_context_in.clk)
  begin
    if rising_edge(ctor_lvt_context_in.clk) then
      if ctor_lvt_context_in.rst = '1' then
        ctor_readdata <= (others => '0');
      elsif ctor_enable and not is_x(ctor_address) then
        if to_integer(unsigned(ctor_address)) < 3 then
          if ctor_writeenable then
            cells(to_integer(unsigned(ctor_address))) <= ctor_writedata;
          else
            ctor_readdata <= cells(to_integer(unsigned(ctor_address)));
          end if;
        end if;
      end if;
    end if;
  end process;
end;

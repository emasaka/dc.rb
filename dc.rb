#!/usr/bin/env ruby

# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2, or (at your option)
# any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, you can either send email to this
# program's author (see below) or write to:
#   The Free Software Foundation, Inc.
#   51 Franklin Street, Fifth Floor
#   Boston, MA 02110-1301  USA

class DCNotImplemented < StandardError; end
class DCStackEmpty < StandardError; end
class DCEofError < StandardError; end
class DCInvalidParam < StandardError; end

class Stack
  def initialize
    @stack = []
    @depth = 0
  end

  attr_reader :depth

  def clear
    @stack.clear
    @depth = 0
  end

  def push(x)
    @stack[@depth] = x
    @depth += 1
  end

  def pop
    raise DCStackEmpty if @depth == 0
    @stack[@depth -= 1]
  end

  def peek
    raise DCStackEmpty if @depth == 0
    @stack[@depth - 1]
  end

  def each
    (@depth - 1).downto(0) do |i|
      yield @stack[i]
    end
  end
end

class Register
  def initialize
    @stack = Stack.new
  end

  attr_accessor :val

  def pop
    x = @val
    @val = @stack.pop
    x
  end

  def push(x)
    @stack.push(@val)
    @val = x
  end
end

class DC
  DC_IBASE_MAX = 16

  def initialize
    @stack = Stack.new
    @registers = {}
    @arrays = {}

    @scale = 0
    @ibase = 10
    @obase = 10
    @scale = 0

    @unwind_depth = 0
  end

  def dc_binop(op)
    x1 = @stack.pop
    x2 = @stack.pop
    @stack.push(x2.send(op, x1))
  end

  def dc_binop2(op)
    x1 = @stack.pop
    x2 = @stack.pop
    r1, r2 = x2.send(op, x1)
    @stack.push(r1)
    @stack.push(r2)
  end

  def dc_cmpop
    x1 = @stack.pop
    x2 = @stack.pop
    x1 <=> x2
  end

  def dc_print(x, newline)
    print(x.kind_of?(Integer) ? x.to_s(@obase).upcase : x)
    print "\n" if newline
  end

  def val_to_char(x)
    if x.kind_of?(String)
      x[0]
    elsif x.kind_of?(Numeric)
      x.to_i.chr
    end
  end

  def dc_dump_num(x)
    dc_print(val_to_char(x), false)
  end

  def tell_scale(n)
    # TODO:
    raise DCNotImplemented
  end

  def tell_length(n)
    if n.kind_of?(Integer)
      n.to_s(@obase).size
    elsif n.kind_of?(Float)
      n.to_s.delete('.').size
    elsif n.kind_of?(String)
      n.size
    end
  end

  def dc_func(c, peekc, negcmp)
    case c
    when '0' .. '9', 'A' .. 'F', '_', '.'
      :DC_INT
    when ' ', "\t", "\n"
      :DC_OKAY
    when '+'
      dc_binop(:+)
      :DC_OKAY
    when '-'
      dc_binop(:-)
      :DC_OKAY
    when '*'
      dc_binop(:*)
      :DC_OKAY
    when '/'
      dc_binop(:/)
      :DC_OKAY
    when '%'
      dc_binop(:%)
      :DC_OKAY
    when '~'
      dc_binop2(:divmod)
      :DC_OKAY
    when '|'
      # TODO:
      raise DCNotImplemented
    when '^'
      dc_binop(:**)
      :DC_OKAY
    when '<'
      raise DCEofError if peekc == nil
      if (dc_cmpop <  0) == !negcmp
        :DC_EVALREG
      else
        :DC_EATONE
      end
    when '='
      raise DCEofError if peekc == nil
      if (dc_cmpop == 0) == !negcmp
        :DC_EVALREG
      else
        :DC_EATONE
      end
    when '>'
      raise DCEofError if peekc == nil
      if (dc_cmpop() >  0) == !negcmp
        :DC_EVALREG
      else
        :DC_EATONE
      end
    when '?'
      # TODO:
      raise DCNotImplemented
    when '['
      :DC_STR
    when '!'
      if peekc == '<' || peekc == '=' || peekc == '>'
        :DC_NEGCMP
      else
        :DC_SYSTEM
      end
    when '#'
      :DC_COMMENT
    when 'a'
      @stack.push(val_to_char(@stack.pop))
      :DC_OKAY
    when 'c'
      @stack.clear
      :DC_OKAY
    when 'd'
      @stack.push(@stack.peek)
      :DC_OKAY
    when 'f'
      @stack.each {|x| dc_print(x, true) }
      :DC_OKAY
    when 'i'
      x = @stack.pop.to_i
      raise DCInvalidParam unless 2 <= x  &&  x <= DC_IBASE_MAX
      @ibase = x
      :DC_OKAY
    when 'k'
      x = @stack.pop.to_i
      raise DCInvalidParam unless x >= 0
      @scale = x
      :DC_OKAY
    when 'l'
      raise DCEofError if peekc == nil
      @stack.push(@registers.fetch(peekc).val)
      :DC_EATONE
    when 'n'
      dc_print(@stack.pop, false)
      :DC_OKAY
    when 'o'
      x = @stack.pop.to_i
      raise DCInvalidParam unless x > 1
      @obase = x
      :DC_OKAY
    when 'p'
      dc_print(@stack.peek, true)
      :DC_OKAY
    when 'q'
      @unwind_depth = 1
      :DC_QUIT
    when 'r'
      x1 = @stack.pop
      x2 = @stack.pop
      @stack.push(x1)
      @stack.push(x2)
      :DC_OKAY
    when 's'
      raise DCEofError if peekc == nil
      (@registers[peekc] ||= Register.new).val = @stack.pop
      :DC_EATONE
    when 'v'
      @stack.push(Math.sqrt(@stack.pop))
      :DC_OKAY
    when 'x'
      :DC_EVALTOS
    when 'z'
      @stack.push(@stack.depth)
      :DC_OKAY
    when 'I'
      @stack.push(@ibase)
      :DC_OKAY
    when 'K'
      @stack.push(@scale)
      :DC_OKAY
    when 'L'
      raise DCEofError if peekc == nil
      @stack.push(@registers.fetch(peekc).pop)
      :DC_EATONE
    when 'O'
      @stack.push(@obase)
      :DC_OKAY
    when 'P'
      x = @stack.pop
      if x.kind_of?(Numeric)
        dc_dump_num(x)
      elsif x.kind_of?(String)
        dc_print(x, false)
      end
      :DC_OKAY
    when 'Q'
      @unwind_depth = @stack.pop.to_i
      raise DCInvalidParam unless @unwind_depth > 0
      @unwind_depth -= 1
      :DC_QUIT
    when 'S'
      raise DCEofError if peekc == nil
      @registers.fetch(peekc).push(@stack.pop)
      :DC_EATONE;
    when 'X'
      x = @stack.pop
      @stack.push(x.kind_of?(Numeric) ? tell_scale(x) : 0)
      :DC_OKAY
    when 'Z'
      x = @stack.pop
      @stack.push(tell_length(x))
      :DC_OKAY
    when ':'
      raise DCEofError if peekc == nil
      idx = @stack.pop.to_i
      val = @stack.pop
      (@arrays[peekc] ||= []) [idx] = val
      :DC_EATONE
    when ';'
      raise DCEofError if peekc == nil
      idx = @stack.pop.to_i
      @stack.push(@arrays.fetch(peekc)[idx])
      :DC_EATONE
    else
      raise DCNotImplemented
    end
  end

  def parse_num(str, idx)
    # str[idx] must be number character
    if m = /_?[\dA-F.]+/.match(str, idx)
      s = m.to_s.sub(/_/, '-')
      if s =~ /\./
        [s.to_f, m.end(0)]
      else
        [s.to_i(@ibase), m.end(0)]
      end
    else
      [nil, idx]
    end
  end

  def parse_str(str, idx)
    count = 1
    p = idx
    while p < str.size && count > 0
      c = str[p]
      if c == ']'
        count -= 1
      elsif c == '['
        count += 1
      end
      p += 1
    end
    [str[idx...(p - 1)], p]
  end

  def skip_past_eol(str, idx)
    i = str.index("\n", idx)
    i ? i + 1 : str.size
  end

  def skip_whitespace(str, idx)
    while idx < str.size && /[\s#]/ =~ (c = str[idx])
      if c == '#'
        idx = skip_past_eol(str, idx)
      else
        idx += 1
      end
    end
    idx
  end

  def call_macro(macro, str, idx, tail_depth)
    idx = skip_whitespace(str, idx)
    if ! macro.kind_of?(String)
      @stack.push(macro)
      [str, idx, tail_depth, :DC_OKAY]
    elsif idx == str.size
      # tail call
      [macro, 0, tail_depth + 1, nil]
    elsif evalstr(macro) == :DC_QUIT
      if @unwind_depth > 0
        @unwind_depth -= 1
        [str, idx, tail_depth, :DC_QUIT]
      else
        [str, idx, tail_depth, :DC_OKAY]
      end
    else
      [str, idx, tail_depth, nil]
    end
  end

  def evalstr(string)
    idx = 0
    tail_depth = 1
    next_negcmp = false

    while idx < string.size
      c = string[idx]
      idx += 1
      peekc = string[idx]
      negcmp = next_negcmp
      next_negcmp = false

      case dc_func(c, peekc, negcmp)
      when :DC_OKAY
        # do nothing
      when :DC_EATONE
        idx += 1
      when :DC_EVALREG
        idx += 1
        x = @registers.fetch(peekc).val
        string, idx, tail_depth, ret = call_macro(x, string, idx, tail_depth)
        return ret if ret
      when :DC_EVALTOS
        x = @stack.pop
        string, idx, tail_depth, ret = call_macro(x, string, idx, tail_depth)
        return ret if ret
      when :DC_QUIT
        if @unwind_depth >= tail_depth
          @unwind_depth -= tail_depth
          return :DC_QUIT
        else
          return :DC_OKAY
        end
      when :DC_INT
        n, idx = parse_num(string, idx - 1)
        @stack.push(n)
      when :DC_STR
        str, idx = parse_str(string, idx)
        @stack.push(str)
      when :DC_SYSTEM
        i = string.index("\n", idx) || string.size
        system(string[idx...i])
        idx = i + 1
      when :DC_COMMENT
        idx = skip_past_eol(string, idx)
      when :DC_NEGCMP
        next_negcmp = true
      end
    end
    :DC_OKAY
  end
end

if __FILE__ == $0
  dc = DC.new.evalstr ARGF.read
end

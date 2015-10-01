defmodule Socex.Shell do
	use Silverb, 	[
						{"@green", IO.ANSI.green},
						{"@cyan", IO.ANSI.cyan},
						{"@yellow", IO.ANSI.yellow},
						{"@magenta", IO.ANSI.magenta},
					]

	def go, do: ((IO.gets(prompt) |> String.strip |> Socex.Api.command); go)
	defp prompt do
		case Socex.Api.cur_state do
			%Socex{state: "menu"} -> "cmd> "
			%Socex{state: "dialog", current_dialog: %{title: title}} -> "#{title}> "
		end
	end

	def draw_dialogs_list(lst) do
		Stream.with_index(lst)
		|> Stream.map(fn({%{title: title}, index}) -> "#{col(index, @cyan)} #{col(title, @yellow)}" end)
		|> Enum.join("\n")
		|> IO.puts
	end

	defp col(some, col), do: "#{IO.ANSI.reset}#{col}#{some}#{IO.ANSI.reset}"

end
defmodule Socex.Shell do
	use Silverb, 	[
						{"@inverse", IO.ANSI.inverse},
						{"@green", IO.ANSI.green},
						{"@cyan", IO.ANSI.cyan},
						{"@yellow", IO.ANSI.yellow},
						{"@magenta", IO.ANSI.magenta},
						{"@blue", IO.ANSI.blue},
						{"@bright", IO.ANSI.bright},
						{"@all_colors", [IO.ANSI.cyan, IO.ANSI.yellow, IO.ANSI.magenta, IO.ANSI.blue, IO.ANSI.bright, IO.ANSI.magenta_background, IO.ANSI.underline, IO.ANSI.white, IO.ANSI.blue_background]}
					]

	def go, do: ((IO.gets(prompt) |> String.strip |> Socex.Api.command); go)
	def prompt do
		case Socex.Api.cur_state do
			%Socex{state: "menu"} -> "cmd> "
			%Socex{state: "dialog", current_dialog: %{title: title}} -> "#{title}> "
		end
	end

	def draw_dialogs_list([]), do: :ok
	def draw_dialogs_list(lst) do
		Stream.with_index(lst)
		|> Stream.map(fn({%{title: title}, index}) -> "#{col(index, @cyan)} #{col(title, @yellow)}" end)
		|> Enum.join("\n")
		|> IO.puts
	end
	def draw_messages_list([]), do: :ok
	def draw_messages_list(lst) do
		members_cols = 	Stream.map(lst, fn(%{user: user}) -> user end)
						|> Stream.uniq 
						|> Stream.with_index
						|> Enum.reduce(%{}, fn({user, index}, acc) -> 
							case Enum.at(@all_colors, index) do
								nil -> Map.put(acc, user, @cyan)
								color -> Map.put(acc, user, color)
							end
						end)
		Stream.map(lst, fn(%{user: user, body: body, date: date, att: att, resend: resend}) -> 
			user_col = Map.get(members_cols, user)
			"#{col( Exutils.timestamp_to_datetime(date) |> Exutils.prepare_verbose_datetime, @green)} : #{ col(user, user_col) }"
			|> maybe_add_body(body, user_col)
			|> maybe_add_att(att)
			|> maybe_add_resend(resend)
		end)
		|> Enum.join("\n")
		|> IO.puts
	end
	defp col(some, col), do: "#{IO.ANSI.reset}#{col}#{some}#{IO.ANSI.reset}"

	defp maybe_add_body(str, "", _), do: str
	defp maybe_add_body(str, body, color), do: str<>" : #{col(body, color)}"

	defp maybe_add_att(str, nil), do: str
	defp maybe_add_att(str, att), do: str<>" : #{inspect att}"

	defp maybe_add_resend(str, nil), do: str
	defp maybe_add_resend(str, resend), do: str<>" : #{inspect(resend) |> col(@inverse)}"

	def help do
		"\nHello, user. This is crazy console VK chat. Special commands: 'ls' 'cd ..' 'help'. Enjoy!\n"
		|> String.split(" ")
		|> Stream.map(&(col(&1, Enum.shuffle(@all_colors) |> List.first)))
		|> Enum.join(" ")
		|> IO.puts
	end

end
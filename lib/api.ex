defmodule Socex.Api do
	use Silverb, 	[
						{"@ttl", Application.get_env(:socex, :update_ttl)},
						{"@show_commands", ["ls"]}
					]
	use ExActor.GenServer, export: :vk_api
	use Httphex,  [
		host: "https://api.vk.com/method", 
		opts: [],
		encode: :json,
		decode: :json,
		gzip: false,
		client: :httpoison,
		timeout: 60000
	]
	defp sleep, do: :timer.sleep(333)
	defp timeout(%Socex{stamp: stamp}) do
		case @ttl - (Exutils.makestamp - stamp) do
			int when (int > 0) -> int
			_ -> 0
		end
	end
	
	definit do
		{:ok, %Socex{} |> store, 0}
	end
	definfo :timeout, state: fullstate = %Socex{state: "menu", dialogs: dialogs} do
		case dialogs_list do
			{:error, error} -> 
				Socex.error("error due loading dialogs list #{inspect error}")
				{:noreply, HashUtils.set(fullstate, [dialogs: [], stamp: Exutils.makestamp]), @ttl}
			^dialogs ->
				{:noreply, fullstate, @ttl}
			new_dialogs when is_list(new_dialogs) -> 
				Socex.notice("got new dialogs")
				{:noreply, HashUtils.set(fullstate, [dialogs: new_dialogs, stamp: Exutils.makestamp]) |> store, @ttl}
		end
	end
	defcall command(cmd), when: is_binary(cmd), state: fullstate = %Socex{state: "menu", dialogs: dialogs}, timeout: 60000 do
		case Maybe.to_integer(cmd) do
			int when (is_integer(int) and (int >= 0)) -> 
				case Enum.at(dialogs, int) do
					nil -> {:reply, :ok, fullstate, timeout(fullstate)}
					subj -> swith_to_dialog(fullstate, subj)
				end
			"" ->
				{:reply, :ok, fullstate, timeout(fullstate)}
			scom when (scom in @show_commands) ->
				process_show_command(fullstate, scom)
				{:reply, :ok, fullstate, timeout(fullstate)}
			_ ->
				case Enum.filter(dialogs, fn(%{title: title}) -> String.contains?(title, cmd) end ) do
					[] -> {:reply, :ok, fullstate, timeout(fullstate)}
					[subj|_] -> swith_to_dialog(fullstate, subj)
				end
		end
	end
	defp swith_to_dialog(fullstate = %Socex{}, subj) do
		IO.inspect(subj)
		#
		#	TODO
		#
		{:reply, :ok, fullstate, timeout(fullstate)}
	end

	defp store(state = %Socex{}), do: Socex.Tinca.put(state, :curstate, :curstate)
	def cur_state, do: Socex.Tinca.get(:curstate, :curstate)

	defp process_show_command(%Socex{state: "menu", dialogs: dialogs}, "ls"), do: Socex.Shell.draw_dialogs_list(dialogs)

	#
	#	to vk api
	#

	defp dialogs_list do
		sleep
		case %{access_token: Socex.Storage.vk_token} |> http_get(["messages.getDialogs"]) do
			%{response: [_|lst]} -> 
				Stream.map(lst, fn
					ans = %{chat_id: chat_id} when (is_integer(chat_id) and (chat_id > 0)) -> %{chat_id: chat_id, title: Map.get(ans, :title) |> to_string}
					%{uid: uid} when (is_integer(uid) and (uid > 0)) -> %{uid: uid, title: case get_user_name(uid) do nil -> to_string(uid); bin when is_binary(bin) -> bin end }
					_ -> nil
				end)
				|> Enum.filter(&(&1 != nil))
			some -> 
				{:error, some}
		end
	end
	defp get_user_name(uid) when is_integer(uid) do
		case Socex.Tinca.get(uid, :users_names) do
			bin when is_binary(bin) -> 
				bin
			nil -> 
				sleep
				case %{access_token: Socex.Storage.vk_token, user_ids: to_string(uid)} |> http_get(["users.get"]) do
					%{response: [%{first_name: n1, last_name: n2, uid: uid}]} -> Socex.Tinca.put("#{n1} #{n2}", uid, :users_names)
					_ -> nil
				end
		end
	end
	defp messages_list(%{chat_id: chat_id}) do
		sleep
		%{access_token: Socex.Storage.vk_token, chat_id: chat_id}
		|> http_get(["messages.getHistory"])
	end
	defp messages_list(%{uid: uid}) do
		sleep
		%{access_token: Socex.Storage.vk_token, user_id: uid}
		|> http_get(["messages.getHistory"])
	end

end
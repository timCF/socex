defmodule Socex.Api do
	use Silverb, 	[
						{"@ttl", Application.get_env(:socex, :update_ttl)},
						{"@show_commands", ["ls", "help"]},
						{"@mess_count", 200},
						{"@tokens", Application.get_env(:socex, :vk_tokens)}
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
		case dialogs_list_union do
			{:error, error} -> 
				Socex.error("error due loading dialogs list #{inspect error}")
				{:noreply, HashUtils.set(fullstate, [dialogs: [], stamp: Exutils.makestamp]), @ttl}
			^dialogs ->
				{:noreply, fullstate, @ttl}
			new_dialogs when is_list(new_dialogs) -> 
				Socex.Shell.draw_dialogs_list(new_dialogs)
				{:noreply, HashUtils.set(fullstate, [dialogs: new_dialogs, stamp: Exutils.makestamp]), @ttl}
		end
		|> store
	end
	definfo :timeout, state: fullstate = %Socex{state: "dialog", current_dialog: current_dialog, messages: messages} do
		case messages_list(current_dialog) do
			{:error, error} -> 
				Socex.error("error due loading messages list #{inspect error}")
				{:noreply, HashUtils.set(fullstate, [messages: [], stamp: Exutils.makestamp]), @ttl}
			^messages ->
				{:noreply, fullstate, @ttl}
			lst when is_list(lst) -> 
				Socex.Shell.draw_messages_list(lst)
				{:noreply, HashUtils.set(fullstate, [messages: lst, stamp: Exutils.makestamp]), @ttl}
		end
		|> store
	end
	defcall command(scom), when: (scom in @show_commands), state: fullstate = %Socex{}, timeout: 60000 do
		process_show_command(fullstate, scom)
		{:reply, :ok, fullstate, timeout(fullstate)}
		|> store
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
			_ ->
				case Enum.filter(dialogs, fn(%{title: title}) -> String.contains?(title, cmd) end ) do
					[] -> {:reply, :ok, fullstate, timeout(fullstate)}
					[subj|_] -> swith_to_dialog(fullstate, subj)
				end
		end
		|> store
	end
	defcall command("cd .."), state: fullstate = %Socex{state: "dialog"}, timeout: 60000 do
		{:reply, :ok, HashUtils.set(fullstate, [state: "menu"]), timeout(fullstate)}
		|> store
	end
	defcall command(""), state: fullstate = %Socex{}, timeout: 60000 do
		{:reply, :ok, fullstate, timeout(fullstate)}
		|> store
	end
	defcall command(mess), state: fullstate = %Socex{state: "dialog", current_dialog: %{user: user}}, timeout: 60000 do
		case send_message(mess, fullstate, Map.get(@tokens, user)) do
			:ok -> :ok
			{:error, error} -> Socex.error("error due sending message #{inspect error}")
		end
		{:reply, :ok, fullstate, timeout(fullstate)}
		|> store
	end

	defp swith_to_dialog(fullstate = %Socex{}, subj), do: {:reply, :ok, HashUtils.set(fullstate, [current_dialog: subj, state: "dialog"]), timeout(fullstate)}

	defp store({:reply, reply, state = %Socex{}, time}), do: {:reply, reply, state |> store, time}
	defp store({:noreply, state = %Socex{}, time}), do: {:noreply, state |> store, time}
	defp store(state = %Socex{}), do: Socex.Tinca.put(state, :curstate, :curstate)
	def cur_state, do: Socex.Tinca.get(:curstate, :curstate)

	defp process_show_command(%Socex{}, "help"), do: Socex.Shell.help
	defp process_show_command(%Socex{state: "menu", dialogs: dialogs}, "ls"), do: Socex.Shell.draw_dialogs_list(dialogs)
	defp process_show_command(%Socex{state: "dialog", messages: messages}, "ls"), do: Socex.Shell.draw_messages_list(messages)

	#
	#	to vk api
	#

	defp dialogs_list_union do
		Enum.reduce(@tokens, [], fn
			{_, _}, acc = {:error, _} -> acc
			{user, token}, acc -> 
				case dialogs_list(token) do
					acc = {:error, _} -> acc
					lst when is_list(lst) -> acc ++ Enum.map(lst, &(Map.put(&1, :user, user)))
				end
		end)
	end
	defp dialogs_list(token) when is_binary(token) do
		sleep
		case %{access_token: token} |> http_get(["messages.getDialogs"]) do
			%{response: [_|lst]} -> 
				Stream.map(lst, fn
					ans = %{chat_id: chat_id} when (is_integer(chat_id) and (chat_id > 0)) -> %{chat_id: chat_id, title: Map.get(ans, :title) |> to_string}
					%{uid: uid} when (is_integer(uid) and (uid > 0)) -> %{uid: uid, title: get_user_name(uid, token, to_string(uid))}
					_ -> nil
				end)
				|> Enum.filter(&(&1 != nil))
			some -> 
				{:error, some}
		end
	end
	defp get_user_name(uid, token, default) when is_integer(uid) do
		case Socex.Tinca.get(uid, :users_names) do
			bin when is_binary(bin) -> 
				bin
			nil -> 
				sleep
				case %{access_token: token, user_ids: to_string(uid)} |> http_get(["users.get"]) do
					%{response: [%{first_name: n1, last_name: n2, uid: uid}]} -> Socex.Tinca.put("#{n1} #{n2}", uid, :users_names)
					_ -> default
				end
		end
	end


	defp messages_list(%{chat_id: chat_id, user: user}) do
		sleep
		token = Map.get(@tokens, user)
		%{access_token: token, chat_id: chat_id, count: @mess_count}
		|> http_get(["messages.getHistory"])
		|> parse_mess_list(token)
	end
	defp messages_list(%{uid: uid, user: user}) do
		sleep
		token = Map.get(@tokens, user)
		%{access_token: token, user_id: uid, count: @mess_count}
		|> http_get(["messages.getHistory"])
		|> parse_mess_list(token)
	end
	defp parse_mess_list(%{response: [_|lst = [_|_]]}, token) do
		Enum.reduce(lst, [], fn
			el = %{from_id: uid, body: body, date: stamp}, acc when (is_integer(uid) and (uid >= 0) and is_binary(body) and is_integer(stamp) and (stamp >= 0)) -> [%{user: get_user_name(uid, token, to_string(uid)), body: String.strip(body), date: :timer.seconds(stamp) + :timer.hours(3), att: Map.get(el, :attachment), resend: Map.get(el, :fwd_messages)}|acc]
			_, acc -> acc
		end)
	end
	defp parse_mess_list(some, _), do: {:error, some}


	defp send_message(bin, %Socex{current_dialog: %{chat_id: chat_id}}, token) when is_binary(bin) do
		sleep
		%{access_token: token, chat_id: chat_id, message: bin}
		|> http_get(["messages.send"])
		|> parse_mess_req
	end
	defp send_message(bin, %Socex{current_dialog: %{uid: user_id}}, token) when is_binary(bin) do
		sleep
		%{access_token: token, user_id: user_id, message: bin}
		|> http_get(["messages.send"])
		|> parse_mess_req
	end
	defp parse_mess_req(%{response: int}) when (is_integer(int) and (int >= 0)), do: :ok
	defp parse_mess_req(some), do: {:error, some}

end
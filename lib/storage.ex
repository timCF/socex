defmodule Socex.Storage do
	use Silverb
	def vk_token, do: Application.get_env(:socex, :vk_token)
end
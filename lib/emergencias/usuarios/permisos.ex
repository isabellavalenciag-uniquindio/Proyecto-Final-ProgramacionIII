defmodule Permisos do
  @moduledoc """
  Qué comandos puede ejecutar cada tipo de usuario.

  Los roles son acumulativos: un voluntario puede todo lo del ciudadano, un
  coordinador todo lo del voluntario, y el administrador todo.

  | Rol           | Agrega                                                      |
  |---------------|-------------------------------------------------------------|
  | (todos)       | consultar y listar                                          |
  | ciudadano     | pedir ayuda, reportar personas y mascotas, dejar mensajes   |
  | voluntario    | ingresos/salidas de albergue, buscar coincidencias          |
  | coordinador   | zonas, recursos, asignaciones, transferencias, albergues    |
  | administrador | ver usuarios y su actividad                                 |
  """

  @orden [:ciudadano, :voluntario, :coordinador, :administrador]

  @base [
    :disconnect, :summary, :list_needs, :pending_needs, :list_resources, :critical_resources,
    :find_person, :list_family_messages, :check_shelter, :list_shelters, :list_pets,
    :list_zones, :zone_status
  ]

  @por_rol %{
    ciudadano: [:register_need, :report_person, :send_family_message, :report_pet],
    voluntario: [:register_entry, :register_exit, :match_pets, :update_person, :mark_message],
    coordinador: [
      :register_zone, :register_sector, :register_point, :register_resource, :resource_in,
      :resource_out, :assign_resource, :transfer_resource, :need_status, :cancel_need,
      :register_shelter, :shelter_link, :shelter_ranking, :confirm_match
    ],
    administrador: [:list_users, :activity]
  }

  @doc "Comandos permitidos para un tipo de usuario."
  @spec comandos(atom()) :: [atom()]
  def comandos(tipo) do
    case Enum.find_index(@orden, &(&1 == tipo)) do
      nil -> []
      indice -> @base ++ Enum.flat_map(Enum.take(@orden, indice + 1), &Map.fetch!(@por_rol, &1))
    end
  end

  @doc """
  Indica si el tipo de usuario puede ejecutar el comando.

  ## Ejemplos

      iex> Permisos.permitido?(:coordinador, :assign_resource)
      true

      iex> Permisos.permitido?(:ciudadano, :assign_resource)
      false
  """
  @spec permitido?(atom(), atom()) :: boolean()
  def permitido?(tipo, comando), do: comando in comandos(tipo)
end

defmodule Emergencias.Application do
  @moduledoc """
  Aplicación OTP del sistema. Inicia el supervisor raíz con todos los procesos.

  ## Árbol de supervisión

      Emergencias.Supervisor (:one_for_one)
      ├── Persistencia            (GenServer: serializa escrituras a archivos)
      ├── Zonas                   (GenServer)
      ├── Inventario              (GenServer único: evita la sobreasignación)
      ├── Necesidades             (GenServer)
      ├── AlberguesSupervisor (:rest_for_one)
      │   ├── Registry            (nombres de los procesos de albergue)
      │   ├── AlbergueSupervisor  (DynamicSupervisor: un proceso por albergue)
      │   └── AlbergueRecuperador (reconstruye los albergues)
      ├── Task.Supervisor         (tareas paralelas)
      └── Usuarios, Personas, Mascotas   (parte B, se inician si existen)

  `Persistencia` va primero porque los demás procesos leen sus datos de allí
  en `init/1`.
  """
  use Application

  # Módulos de la parte B: se agregan solo si ya están compilados y
  # exponen `start_link/1`.
  @modulos_b [Usuarios, Personas, Mascotas]

  @impl true
  def start(_type, _args) do
    hijos =
      [
        Persistencia,
        Zonas,
        Inventario,
        Necesidades,
        AlberguesSupervisor,
        {Task.Supervisor, name: Emergencias.TareasSupervisor}
      ] ++ hijos_b()

    Supervisor.start_link(hijos, strategy: :one_for_one, name: Emergencias.Supervisor)
  end

  defp hijos_b do
    Enum.filter(@modulos_b, fn modulo ->
      Code.ensure_loaded?(modulo) and function_exported?(modulo, :start_link, 1)
    end)
  end
end

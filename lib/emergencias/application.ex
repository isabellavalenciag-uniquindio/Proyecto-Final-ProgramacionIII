defmodule Emergencias.Application do
  @moduledoc """
  Aplicación OTP del sistema. Inicia el supervisor raíz con todos los procesos.

  ## Árbol de supervisión

      Emergencias.Supervisor (:one_for_one)
      ├── Persistencia            (GenServer: serializa escrituras a archivos)
      ├── Registry                (nombres de los procesos de albergue)
      ├── Zonas                   (GenServer)
      ├── Inventario              (GenServer único: evita la sobreasignación)
      ├── Necesidades             (GenServer)
      ├── AlbergueSupervisor      (DynamicSupervisor: un proceso por albergue)
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
        {Registry, keys: :unique, name: Emergencias.RegistroAlbergues},
        Zonas,
        Inventario,
        Necesidades,
        AlbergueSupervisor,
        {Task.Supervisor, name: Emergencias.TareasSupervisor}
      ] ++ hijos_b()

    resultado = Supervisor.start_link(hijos, strategy: :one_for_one, name: Emergencias.Supervisor)

    # Los albergues son procesos dinámicos: se recrean desde el archivo
    Albergues.cargar()
    resultado
  end

  defp hijos_b do
    Enum.filter(@modulos_b, fn modulo ->
      Code.ensure_loaded?(modulo) and function_exported?(modulo, :start_link, 1)
    end)
  end
end

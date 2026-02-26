--!strict
-- Compatibility shim: the old `EnableRagdollOnDeath` script previously
-- required a ModuleScript under ReplicatedStorage/Modules/RagdollService.
-- You deleted the Modules folder; ragdoll behaviour is now handled by
-- `ServerScriptService/Ragdoll.server.lua` (single-file server implementation).

-- This script intentionally does nothing to avoid errors from missing
-- ModuleScripts. Keep it in place if other tooling expects this path.

print("EnableRagdollOnDeath: Modules folder removed — using ServerScriptService/Ragdoll.server.lua")
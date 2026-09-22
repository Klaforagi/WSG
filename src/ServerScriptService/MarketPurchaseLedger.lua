-- Pure UpdateAsync transforms. Claims remain separate from inventory so selling a
-- weapon cannot buy the same offer again. Tokens make datastore retries idempotent.
local Ledger = {}
function Ledger.Reserve(old, cycle, slot, token)
    old = type(old) == "table" and old or { cycle = cycle, slots = {} }
    if (tonumber(old.cycle) or -1) > cycle then return old end
    if old.cycle ~= cycle then old = { cycle = cycle, slots = {} } end
    old.slots = old.slots or {}
    if not old.slots[slot] then old.slots[slot] = token end
    return old
end
function Ledger.Release(old, cycle, slot, token)
    if type(old) == "table" and old.cycle == cycle and old.slots and old.slots[slot] == token then
        old.slots[slot] = nil
    end
    return old
end
function Ledger.ReserveStock(old, cycle, prefix, limit, token)
    if type(old) == "table" and old.cycle == cycle then
        for index = 1, limit do
            if old.slots and old.slots[prefix .. index] == token then return old end
        end
    end
    for index = 1, limit do
        local key = prefix .. index
        if type(old) ~= "table" or old.cycle ~= cycle or not old.slots or not old.slots[key] then
            return Ledger.Reserve(old, cycle, key, token)
        end
    end
    return old
end
return Ledger

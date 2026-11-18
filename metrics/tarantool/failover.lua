local checks = require('checks')
local utils = require('metrics.utils')

local collectors_list = {}
local source
local instances = {}

--- Internal integration interface. Register, replace, or detach the source.
-- The EE coordinator calls set_source(provider), or set_source(nil) to detach.
-- Registration does not enable collection. Replacing or detaching the source
-- immediately clears its observations. Disabling the group clears its callback
-- and collectors, but retains the source for re-enabling.
--
-- The provider returns current cached monitoring state, for example:
-- {
--     alias = 'coordinator-uuid',
--     active = true,
--     replicasets = {
--         ['rs-001'] = {
--             ['instance-001'] = 'alive',
--             ['instance-002'] = 'uncallable',
--             ['instance-003'] = false,
--         },
--     },
-- }
-- active is a boolean. Each replicaset maps instance names to status strings,
-- or false for missing status. Omit instances that are no longer monitored,
-- but include every monitored instance, even those ineligible to become master.
-- The optional alias is identity metadata: this collector ignores it. The
-- integration sets the default alias through global labels and merges user
-- labels over it.
--
-- The provider must not yield, access the network, run expensive checks, or
-- change failover state. Collection does not mutate the returned snapshot.
-- Provider errors propagate to the caller.
---@param snapshot_source function? Non-yielding, read-only snapshot provider.
local function set_source(snapshot_source)
    checks('?function')
    utils.delete_collectors(collectors_list)
    instances = {}
    source = snapshot_source
end

local function update()
    if source == nil then
        return
    end

    local snapshot = source()

    if collectors_list.instance_status ~= nil then
        for _, labels in ipairs(instances) do
            collectors_list.instance_status:remove(labels)
        end
    end
    instances = {}

    collectors_list.coordinator_active = utils.set_gauge('coordinator_active',
        'Whether the coordinator owns the lock', snapshot.active and 1 or 0,
        nil, 'tarantool_', {default = true})

    for replicaset, members in pairs(snapshot.replicasets) do
        for instance, status in pairs(members) do
            local labels = {replicaset = replicaset, instance = instance}
            collectors_list.instance_status = utils.set_gauge('instance_status',
                'Whether the monitored instance is alive',
                status == 'alive' and 1 or 0, labels, 'tarantool_',
                {default = true})
            table.insert(instances, labels)
        end
    end
end

return {
    set_source = set_source,
    update = update,
    list = collectors_list,
}

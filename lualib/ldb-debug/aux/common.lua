local lo = require('ldb-debug/utils/lodash')
local rdebug = require('remotedebug')

local function expand_value(value, cache)

    -- 基本类型，自身就是值
    if type(value) ~= 'userdata' then
        return value
    end

    -- 非基本类型，rdebug.value() 返回一个表示地址的字符串
    -- 相当于在 host vm 里 tostring()
    local orig_address = rdebug.value(value)

    -- 避免递归，从缓存取出已经展开过的
    local cache_key = orig_address
    local cache_value = cache[cache_key]
    if cache_value then
        return cache_value
    end

    local orig_type = rdebug.type(value)

    if orig_type == 'function' then
        -- 反正无法直接执行 host vm 里的函数
        -- 就构造一个返回表示地址的字符串的函数
        local func = lo.constant(orig_address)
        cache[cache_key] = func
        return func
    end

    if orig_type == 'table' then
        local tbl = {}
        cache[cache_key] = tbl

        local next_key, next_value
        while true do
            next_key, next_value = rdebug.next(value, next_key)
            if next_key == nil then
                break
            end
            tbl[next_key] = expand_value(next_value, cache)
        end

        return tbl
    end

    -- 如果原本就是一个 userdata 类型，暂时不知道怎么处理好
    if orig_type == 'userdata' then
        return nil
    end

    return nil
end

local expand_to_array = function(items)
    local cache = {}
    local ret = {}
    for _, item in ipairs(items) do
        local value = expand_value(item[2], cache)
        table.insert(ret, value)
    end
    return ret
end

local expand_to_dict = function(items)
    local cache = {}
    local ret = {}
    local temporaries = {}
    local varargs = {}
    local retargs = {}

    for _, item in ipairs(items) do
        local name = item[1]
        local value = expand_value(item[2], cache)

        if name == '(*temporary)' then
            table.insert(temporaries, value)
        elseif name == '(*vararg)' then
            table.insert(varargs, value)
        elseif name == '(*retarg)' then
            table.insert(retargs, value)
        else
            ret[name] = value
        end
    end

    if #temporaries > 0 then
        ret['(*temporary)'] = temporaries
    end
    if #varargs > 0 then
        ret['(*vararg)'] = varargs
    end
    if #retargs > 0 then
        ret['(*retarg)'] = retargs
    end

    return ret
end

return {
    expand_to_array = expand_to_array,
    expand_to_dict = expand_to_dict,
}

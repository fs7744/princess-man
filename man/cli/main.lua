rawset(_G, 'lfs', false)

local function env(home)
    local pkg_cpath_org = package.cpath
    local pkg_path_org = package.path
    local pkg_cpath = home .. "/deps/lib64/lua/5.1/?.so;" .. home ..
        "/deps/lib/lua/5.1/?.so;"

    local pkg_path = home .. "/src/?.lua;" .. home .. "/?/init.lua;" .. home ..
        "/deps/share/lua/5.1/?/init.lua;" .. home ..
        "/deps/share/lua/5.1/?.lua;;"

    package.cpath = pkg_cpath .. pkg_cpath_org
    package.path = pkg_path .. pkg_path_org

    return {
        home = home,
        openresty_args = [[openresty -p ]] .. home .. [[ -c ]],
        pkg_cpath = package.cpath,
        pkg_path = package.path
    }
end

local e = env(arg[1])

local cmds = {
    {
        name = "version",
        description = "show princess man version",
        fn = function()
            print(require('man.core').version)
        end
    },
    {
        name = "init",
        description = "init nginx conf",
        options = {
            {
                name = "conf",
                short_name = "c",
                description = "yaml conf",
                required = true,
                default = e.home .. 'man.yaml'
            },
            {
                name = "output",
                short_name = "o",
                description = "output generate nginx.conf",
                required = true,
                default = e.home .. '/nginx.conf'
            }
        },
        fn = function(env, args)
            return require('man.cli.init_conf').generate(env, args)
        end
    }
}

require("man.cli.cmd").execute(cmds, e, arg)

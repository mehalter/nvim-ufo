local M = {}
local cmd = vim.cmd
local api = vim.api

local utils      = require('ufo.utils')
local fold       = require('ufo.fold')
local decorator  = require('ufo.decorator')
local highlight  = require('ufo.highlight')
local preview    = require('ufo.preview')
local disposable = require('ufo.lib.disposable')
local bufmanager = require('ufo.bufmanager')
local event      = require('ufo.lib.event')

local enabled

---@type UfoDisposable[]
local disposables = {}

local function createEvents()
    cmd('aug Ufo')
    cmd([[
        au!
        au BufEnter * lua require('ufo.lib.event'):emit('BufEnter', vim.api.nvim_get_current_buf())
        au InsertLeave * lua require('ufo.lib.event'):emit('InsertLeave', vim.api.nvim_get_current_buf())
        au TextChanged * lua require('ufo.lib.event'):emit('TextChanged', vim.api.nvim_get_current_buf())
        au BufWritePost * lua require('ufo.lib.event'):emit('BufWritePost', vim.api.nvim_get_current_buf())
        au WinClosed * lua require('ufo.lib.event'):emit('WinClosed', tonumber(vim.fn.expand('<afile>')))
        au CmdlineLeave * lua require('ufo.lib.event'):emit('CmdlineLeave')
        au ColorScheme * lua require('ufo.lib.event'):emit('ColorScheme')
    ]])
    local optionSetArgs = 'vim.api.nvim_get_current_buf(), vim.v.option_old, vim.v.option_new'
    cmd(([[
        au OptionSet buftype lua require('ufo.lib.event'):emit('BufTypeChanged', %s)
        au OptionSet filetype lua require('ufo.lib.event'):emit('FileTypeChanged', %s)
    ]]):format(optionSetArgs, optionSetArgs))
    cmd('aug END')

    return disposable:create(function()
        cmd([[
            au! Ufo
            aug! Ufo
        ]])
    end)
end

local function createCommand()
    cmd([[
        com! UfoEnable lua require('ufo').enable()
        com! UfoDisable lua require('ufo').disable()
        com! UfoInspect lua require('ufo').inspect()
        com! UfoAttach lua require('ufo').attach()
        com! UfoDetach lua require('ufo').detach()
        com! UfoEnableFold lua require('ufo').enableFold()
        com! UfoDisableFold lua require('ufo').disableFold()
    ]])
end

function M.enable()
    if enabled then
        return false
    end
    local ns = api.nvim_create_namespace('ufo')
    createCommand()
    disposables = {}
    table.insert(disposables, createEvents())
    table.insert(disposables, highlight:initialize())
    table.insert(disposables, fold:initialize(ns))
    table.insert(disposables, decorator:initialize(ns))
    table.insert(disposables, preview:initialize(ns))
    table.insert(disposables, bufmanager:initialize())
    enabled = true
    return true
end

function M.disable()
    if not enabled then
        return false
    end
    for _, item in ipairs(disposables) do
        item:dispose()
    end
    enabled = false
    return true
end

function M.inspectBuf(bufnr)
    bufnr = bufnr or api.nvim_get_current_buf()
    local fb = fold.get(bufnr)
    if not fb then
        return
    end
    local msg = {}
    table.insert(msg, 'Buffer: ' .. bufnr)
    table.insert(msg, 'Fold Status: ' .. fb.status)
    local main = fb.providers[1]
    table.insert(msg, 'Main provider: ' .. (type(main) == 'function' and 'external' or main))
    if fb.providers[2] then
        table.insert(msg, 'Fallback provider: ' .. fb.providers[2])
    end
    table.insert(msg, 'Selected provider: ' .. (fb.selectedProvider or 'nil'))
    return msg
end

function M.hasAttached(bufnr)
    bufnr = bufnr or api.nvim_get_current_buf()
    local buf = bufmanager:get(bufnr)
    return buf and buf.attached
end

function M.attach(bufnr)
    bufnr = bufnr or api.nvim_get_current_buf()
    event:emit('BufEnter', bufnr)
end

function M.detach(bufnr)
    bufnr = bufnr or api.nvim_get_current_buf()
    event:emit('BufDetach', bufnr)
end

function M.enableFold(bufnr)
    bufnr = bufnr or api.nvim_get_current_buf()
    local old = fold.setStatus(bufnr, 'start')
    fold.update(bufnr)
    return old
end

function M.disableFold(bufnr)
    bufnr = bufnr or api.nvim_get_current_buf()
    return fold.setStatus(bufnr, 'stop')
end

function M.foldtext()
    local fs = vim.v.foldstart
    local curBufnr = api.nvim_get_current_buf()
    local buf = bufmanager:get(curBufnr)
    local text = buf and buf:lines(fs)[1] or api.nvim_buf_get_lines(curBufnr, fs - 1, fs, true)[1]
    return utils.expandTab(text, vim.bo.ts)
end

return M

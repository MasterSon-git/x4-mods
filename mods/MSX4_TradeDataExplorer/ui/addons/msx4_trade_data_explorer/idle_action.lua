local ffi = require("ffi")
local C = ffi.C

ffi.cdef[[
  uint64_t GetPlayerOccupiedShipID(void);
]]

local tdeOrderIds = {
  MSX4_TradeDataExplorerG = true,
  MSX4_TradeDataExplorerS = true,
}

local targetActions = {
  IDLE_MOVE_TARGET = 1,
  IDLE_FOLLOW_TARGET = 2,
  IDLE_DOCK_TARGET = 3,
}

local actionOptions = {
  { id = 0, text = ReadText(975210, 102), icon = "", displayremoveoption = false },
  { id = 1, text = ReadText(975210, 103), icon = "", displayremoveoption = false },
  { id = 2, text = ReadText(975210, 104), icon = "", displayremoveoption = false },
  { id = 3, text = ReadText(975210, 105), icon = "", displayremoveoption = false },
  { id = 4, text = ReadText(975210, 106), icon = "", displayremoveoption = false },
}

local messageLevelOptions = {
  { id = 0, text = ReadText(975210, 107), icon = "", displayremoveoption = false },
  { id = 1, text = ReadText(975210, 108), icon = "", displayremoveoption = false },
  { id = 2, text = ReadText(975210, 109), icon = "", displayremoveoption = false },
  { id = 3, text = ReadText(975210, 110), icon = "", displayremoveoption = false },
}

local function getNumberParam(order, name, fallback)
  for _, orderparam in ipairs(order.params or {}) do
    if orderparam.name == name then
      return tonumber(orderparam.value) or fallback
    end
  end
  return fallback
end

local function isTradeDataExplorerOrder(order)
  return order and order.orderdefref and tdeOrderIds[order.orderdefref.id] == true
end

local function setNumberChoice(menu, orderidx, paramidx, listidx, instance, choice)
  -- The Vanilla number-parameter handler owns default-order planning, the
  -- validity check and frame refresh.  Only its presentation is replaced.
  return menu.slidercellSetOrderParam(orderidx, paramidx, listidx, tonumber(choice), instance)
end

local function displayNumberChoice(menu, ftable, orderidx, order, paramidx, param, listidx, instance, options, selectedOption)
  local selectedorder = menu.infoTablePersistentData[instance].selectedorder
  local row = ftable:addRow({ orderidx, paramidx, listidx }, {})
  if selectedorder and selectedorder[1] == orderidx and selectedorder[2] == paramidx and selectedorder[3] == listidx then
    menu.selectedRows["infotable" .. instance] = row.index
    menu.selectedCols["infotable" .. instance] = nil
  end

  local isplayeroccupiedship = menu.infoSubmenuObject == C.GetPlayerOccupiedShipID()
  local paramactive = true
  if orderidx == "default" then
    paramactive = (menu.infoTableData[instance].commander == nil) and (not isplayeroccupiedship)
  end
  if paramactive and ((param.inputparams and param.inputparams.playerreadonly) or param.playerreadonly) then
    if param.inputparams and param.inputparams.playerreadonly then
      paramactive = param.inputparams.playerreadonly ~= 1
    elseif param.playerreadonly then
      paramactive = param.playerreadonly ~= 1
    end
  end

  local active = paramactive and (not isplayeroccupiedship) and (((order.state == "setup") and (paramidx <= (order.actualparams + 1))) or ((order.state ~= "setup") and param.editable))
  local labelcol = menu.infoTableData[instance].hasloop and 4 or 2
  row[labelcol]:setColSpan(menu.infoTableData[instance].hasloop and 1 or 3):createText("  " .. param.text .. ReadText(1001, 120))
  row[5]:setColSpan(8):createDropDown(options, {
    active = active,
    height = Helper.standardTextHeight,
    startOption = selectedOption,
  }):setTextProperties({ fontsize = Helper.standardFontSize, halign = "center" })
  row[5].handlers.onDropDownActivated = function () menu.noupdate = true end
  row[5].handlers.onDropDownConfirmed = function (_, choice)
    return setNumberChoice(menu, orderidx, paramidx, listidx, instance, choice)
  end
end

local function init()
  local menu = Helper.getMenu("MapMenu")
  if not menu then
    DebugError("MSX4 Trade Data Explorer: MapMenu was not available for idle-action UI registration.")
    return
  end
  if menu.msx4TradeDataExplorerIdleActionRegistered then
    return
  end

  local vanillaDisplayOrderParam = menu.displayOrderParam
  menu.displayOrderParam = function (ftable, orderidx, order, paramidx, param, listidx, instance)
    if isTradeDataExplorerOrder(order) then
      if param.name == "IDLE_ACTION" then
        return displayNumberChoice(menu, ftable, orderidx, order, paramidx, param, listidx, instance, actionOptions, getNumberParam(order, "IDLE_ACTION", 0))
      elseif param.name == "SHOW_MESSAGES" or param.name == "WRITE_TO_LOG" then
        return displayNumberChoice(menu, ftable, orderidx, order, paramidx, param, listidx, instance, messageLevelOptions, getNumberParam(order, param.name, 0))
      end

      local requiredAction = targetActions[param.name]
      if requiredAction and getNumberParam(order, "IDLE_ACTION", 0) ~= requiredAction then
        return
      end
    end

    return vanillaDisplayOrderParam(ftable, orderidx, order, paramidx, param, listidx, instance)
  end

  menu.msx4TradeDataExplorerIdleActionRegistered = true
end

init()

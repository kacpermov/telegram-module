local signal = require("./modules/GoodSignal")

local net = require("@lune/net")
local serde = require("@lune/serde")
local task = require("@lune/task")


local function request(token, endpoint, body, method: "GET" | "POST")
    body=body or {};body=serde.encode("json", body);
    method = method or "GET"
    local s,r=pcall(function()return net.request({url="https://api.telegram.org/bot"..token.."/"..endpoint,method=method,body=body,headers={["Content-Type"]="application/json"}})end)

    if not s then return error(r) end

    local json = serde.decode("json", r.body)

    if not json.ok then return error(r.body) end

    return json
end

local tg = {}  
tg.__index = tg

function tg.new(token)
    return setmetatable({
        token=token;
        onMessageReceived=signal.new();
        onCallbackQuery=signal.new();
        onStart=signal.new();
        onInlineQuery=signal.new();
        _ActivePollingHandler=false;
        _Answered={};
    }, tg.__index)
end

function tg:sendMessage(chatId, message)
    return request(self.token, 'sendMessage', {
            ["chat_id"]=chatId,
            ["text"]=message
    }, "POST")
end

function tg:sendMessageMarkup(chatId, message, markup)
    return request(self.token, 'sendMessage', {
            ["chat_id"]=chatId,
            ["text"]=message,
            ["parse_mode"]="MarkdownV2",
            ["reply_markup"]=markup
    }, "POST")
end

function tg:sendLocation(chatId, lat, long, period)
    return request(self.token, 'sendLocation', {
            ["chat_id"]=chatId,
            ["latitude"]=lat,
            ["longitude"]=long,
            ["live_period"]=period
    }, "POST")
end

function tg:editMessageText(chatId, messageId, message)
    return request(self.token, 'editMessageText', {
            ["chat_id"]=chatId,
            ["message_id"]=messageId,
            ["text"]=message
    }, "POST")
end

function tg:editMessageReplyMarkup(chatId, messageId, markup)
    return request(self.token, 'editMessageReplyMarkup', {
            ["chat_id"]=chatId,
            ["message_id"]=messageId,
            ["reply_markup"]=markup

    }, "POST")
end

function tg:editLocation(chatId, messageId ,lat, long)
    return request(self.token, 'editMessageLiveLocation', {
            ["chat_id"]=chatId,
            ["message_id"] = messageId;
            ["latitude"]=lat,
            ["longitude"]=long
    }, "POST")
end

function tg:stopLocation(chatId, messageId)
    return request(self.token, 'stopMessageLiveLocation', {
            ["chat_id"]=chatId,
            ["message_id"]=messageId,
    }, "POST")
end

function tg:deleteMessage(chatId, messageId)
    return request(self.token, 'deleteMessage', {
            ["chat_id"]=chatId,
            ["message_id"]=messageId,
    }, "POST")
end

function tg:deleteMessages(chatId, messageIds)
    return request(self.token, 'deleteMessages', {
            ["chat_id"]=chatId,
            ["message_id"]=messageIds,
    }, "POST")
end

function tg:_update(offset)
    if not offset then
        return request(self.token, 'getUpdates', {}, "POST")
    else
        return request(self.token, 'getUpdates', {offset=offset}, "POST")
    end
end

function tg:_getLatestId()
    local u = self:_update()
    local highest = 0
    for _, v in ipairs(u.result) do
        if v.update_id > highest then
            highest = v.update_id
        end
    end

    return highest
end

function tg:answerInlineQuery(queryId, results, cacheTime)
    return request(self.token, 'deleteMessage', {
            ["inline_query_id"]=queryId,
            ["results"]=results,
            ["cache_time"]=cacheTime
    }, "POST")
end

function tg:answerCallbackQuery(queryId, text, showAlert)
    return request(self.token, 'deleteMessage', {
            ["callback_query_id"]=queryId,
            ["text"]=text,
            ["show_alert"]=showAlert
    }, "POST")
end

function tg:getMe()
    return request(self.token, "getMe", {}, "GET")
end

function tg:startPolling()
    if self._ActivePollingHandler then return end
    self._ActivePollingHandler=true

    local higestNumber = self:_getLatestId()
    task.spawn(function()
        while task.wait(1.1) do
            local update = self:_update(higestNumber+1)
            
            if update.ok then
                for _, v in ipairs(update.result) do
                    if v.update_id > higestNumber then
                        higestNumber=v.update_id
                    else
                        continue
                    end
                    if v.is_bot then continue end
                    if v.message then
                        self.onMessageReceived:Fire(v.message)
                    elseif v.callback_query then
                        self.onCallbackQuery:Fire(v.callback_query)
                    elseif v.inline_query then
                        self.onInlineQuery:Fire(v.inline_query)
                    end
                end
            end
        end
    end)
    task.spawn(function()
        local g = self:getMe()
        if not g then
            task.wait(1)
            g=tg:getMe()
        end
        self.onStart:Fire(self:getMe())
    end)
end

return tg
--[[
    Название: Змейка
    Автор: Avondale, дискорд - avonda
    
    Чтобы начать игру надо встать на цвета своей команды(если 1 команда то куда угодно на поле) и нажать любую синюю кнопку

    Описание механики: 
        Игроки пытаются собрать яблоки быстрее змейки
        Наступая на змейку игроки теряют здоровье
        
        Нужно собрать 20 яблок(по стандартным настройкам)
        Если змейка соберет 20 яблок быстрее игроков - поражение

        Можно играть либо все в одной команде против змейки, либо до 5 команд по сколько угодно человек
        Побеждает команда которая быстрее всех соберет 20 яблок
        Команде нужно собирать яблоки своего цвета

    Идеи по доработке: 
        Можно сделать настройку интеллекта змейки, например сейчас она бежит к самому дальнему яблоку, добавить настройку чтоб бежала к самому близкому и тд. уровни сложности мб
]]
math.randomseed(os.time())

local CLog = require("log")
local CInspect = require("inspect")
local CHelp = require("help")
local CJson = require("json")
local CTime = require("time")
local CAudio = require("audio")
local CColors = require("colors")

local tGame = {
    Cols = 24,
    Rows = 15, 
    Buttons = {}, 
}
local tConfig = {}

-- стейты или этапы игры
local GAMESTATE_SETUP = 1
local GAMESTATE_GAME = 2
local GAMESTATE_POSTGAME = 3
local GAMESTATE_FINISH = 4

local bGamePaused = false
local iGameState = GAMESTATE_SETUP
local iPrevTickTime = 0

local tGameStats = {
    StageLeftDuration = 0, 
    StageTotalDuration = 0, 
    CurrentStars = 0,
    TotalStars = 0,
    CurrentLives = 1,
    TotalLives = 1,
    Players = { -- максимум 6 игроков
        { Score = 0, Lives = 0, Color = CColors.NONE },
        { Score = 0, Lives = 0, Color = CColors.NONE },
        { Score = 0, Lives = 0, Color = CColors.NONE },
        { Score = 0, Lives = 0, Color = CColors.NONE },
        { Score = 0, Lives = 0, Color = CColors.NONE },
        { Score = 0, Lives = 0, Color = CColors.RED },
    },
    TargetScore = 0,
    StageNum = 0,
    TotalStages = 0,
    TargetColor = CColors.NONE,
}

local tGameResults = {
    Won = false,
}

local tFloor = {} 
local tButtons = {}

local tFloorStruct = { 
    iColor = CColors.NONE,
    iBright = CColors.BRIGHT0,
    bClick = false,
    bDefect = false,
    iWeight = 0,
    bBlocked = false,
    iPixelID = 0,
}
local tButtonStruct = { 
    bClick = false,
    bDefect = false,
}

local tPlayerInGame = {}
local bAnyButtonClick = false
local bCountDownStarted = false

function StartGame(gameJson, gameConfigJson)
    tGame = CJson.decode(gameJson)
    tConfig = CJson.decode(gameConfigJson)

    for iX = 1, tGame.Cols do
        tFloor[iX] = {}    
        for iY = 1, tGame.Rows do
            tFloor[iX][iY] = CHelp.ShallowCopy(tFloorStruct) 
        end
    end

    for _, iId in pairs(tGame.Buttons) do
        tButtons[iId] = CHelp.ShallowCopy(tButtonStruct)
    end

    CGameMode.InitGameMode()
    CGameMode.Announcer()
end

function NextTick()
    if iGameState == GAMESTATE_SETUP then
        GameSetupTick()
    end

    if iGameState == GAMESTATE_GAME then
        GameTick()
    end

    if iGameState == GAMESTATE_POSTGAME then
        PostGameTick()
    end

    if iGameState == GAMESTATE_FINISH then
        return tGameResults
    end    

    CTimer.CountTimers((CTime.unix() - iPrevTickTime) * 1000)
    iPrevTickTime = CTime.unix()
end

function GameSetupTick()
    SetGlobalColorBright(CColors.NONE, tConfig.Bright) -- красим всё поле в один цвет
    SetAllButtonColorBright(CColors.GREEN, tConfig.Bright) 

    local iPlayersReady = 0

    for iPos, tPos in ipairs(tGame.StartPositions) do
        if iPos <= #tGame.StartPositions then
            local iBright = CColors.BRIGHT15
            if CheckPositionClick(tPos, tGame.StartPositionSizeX, tGame.StartPositionSizeY) or (bCountDownStarted and tPlayerInGame[iPos]) then
                tGameStats.Players[iPos].Color = tPos.Color
                iBright = CColors.BRIGHT30
                iPlayersReady = iPlayersReady + 1
                tPlayerInGame[iPos] = true
            else
                tGameStats.Players[iPos].Color = CColors.NONE
                tPlayerInGame[iPos] = false
            end

            CPaint.PlayerZone(iPos, iBright, false)
        end
    end

    if not bCountDownStarted and iPlayersReady > 0 and bAnyButtonClick then
        bCountDownStarted = true
        bAnyButtonClick = false
        iGameState = GAMESTATE_GAME
        CGameMode.StartCountDown(tConfig.GameCountdown)
    end
end

function GameTick()
    SetGlobalColorBright(CColors.NONE, tConfig.Bright) -- красим всё поле в один цвет
    CPaint.Pixels()
    CPaint.Snake()
end

function PostGameTick()
    if CGameMode.bVictory then
        SetGlobalColorBright(tGameStats.Players[CGameMode.iWinnerID].Color, tConfig.Bright)
    else
        SetGlobalColorBright(CColors.RED, tConfig.Bright)
    end
end

function RangeFloor(setPixel, setButton)
    for iX = 1, tGame.Cols do
        for iY = 1, tGame.Rows do
            setPixel(iX , iY, tFloor[iX][iY].iColor, tFloor[iX][iY].iBright)
        end
    end

    for i, tButton in pairs(tButtons) do
        setButton(i, tButton.iColor, tButton.iBright)
    end
end

function SwitchStage()
    
end

--GAMEMODE
CGameMode = {}
CGameMode.iCountdown = 0
CGameMode.bVictory = false
CGameMode.iWinnerID = -1
CGameMode.tPixels = {}
CGameMode.tBlockList = {}

CGameMode.InitGameMode = function()
    tGameStats.TargetScore = tConfig.TargetScore

    CGameMode.LoadBlockList()

    CSnake.Create()
end

CGameMode.Announcer = function()
    CAudio.PlaySync("games/snake-game.mp3")
    CAudio.PlaySync("voices/snake-guide.mp3")

    if #tGame.StartPositions > 1 then
        CAudio.PlaySync("voices/choose-color.mp3")
    end
    CAudio.PlaySync("voices/press-button-for-start.mp3")
end

CGameMode.StartCountDown = function(iCountDownTime)
    CGameMode.iCountdown = iCountDownTime

    CTimer.New(1000, function()
        CAudio.PlaySyncFromScratch("")
        tGameStats.StageLeftDuration = CGameMode.iCountdown

        if CGameMode.iCountdown <= 0 then
            CGameMode.StartGame()
            
            return nil
        else
            CAudio.PlayLeftAudio(CGameMode.iCountdown)
            CGameMode.iCountdown = CGameMode.iCountdown - 1

            return 1000
        end
    end)
end

CGameMode.StartGame = function()
    CAudio.PlaySync(CAudio.START_GAME)
    CAudio.PlayRandomBackground()

    for iPlayerID = 1, #tGame.StartPositions do
        if tPlayerInGame[iPlayerID] then
            CGameMode.PlacePixelForPlayer(iPlayerID)
        end 
    end

    --tGameStats.StageLeftDuration = tConfig.GameTime

    --[[
    CTimer.New(1000, function()
        tGameStats.StageLeftDuration = tGameStats.StageLeftDuration - 1

        if tGameStats.StageLeftDuration <= 0 then
            CGameMode.EndGame(true)
            return nil
        else

            if tGameStats.StageLeftDuration <= 5 then
                CAudio.PlayLeftAudio(tGameStats.StageLeftDuration)
            end

            return 1000
        end
    end)
    ]]
    
    CSnake.Start()
end

CGameMode.PlacePixelForPlayer = function(iPlayerID)
    local iPixelID = #CGameMode.tPixels+1

    CGameMode.tPixels[iPixelID] = {}
    CGameMode.tPixels[iPixelID].iPlayerID = iPlayerID
    CGameMode.tPixels[iPixelID].iX, CGameMode.tPixels[iPixelID].iY = CGameMode.RandomPositionForPixel()

    tFloor[CGameMode.tPixels[iPixelID].iX][CGameMode.tPixels[iPixelID].iY].iPixelID = iPixelID
end

CGameMode.PlayerClickPixel = function(iPixelID)
    if not CGameMode.tPixels[iPixelID].iPlayerID then return end

    local iPlayerID = CGameMode.tPixels[iPixelID].iPlayerID

    CAudio.PlayAsync(CAudio.CLICK)

    tGameStats.Players[iPlayerID].Score = tGameStats.Players[iPlayerID].Score + 1
    if tGameStats.Players[iPlayerID].Score >= tGameStats.TargetScore then
        CGameMode.iWinnerID = iPlayerID
        CGameMode.EndGame(true)
        return;
    end

    tFloor[CGameMode.tPixels[iPixelID].iX][CGameMode.tPixels[iPixelID].iY].iPixelID = 0

    CGameMode.tPixels[iPixelID] = {}

    CGameMode.PlacePixelForPlayer(iPlayerID)
end

CGameMode.RandomPositionForPixel = function()
    local iX, iY = 0, 0

    repeat
        iX = math.random(1, tGame.Cols)
        iY = math.random(1, tGame.Rows)
    until CGameMode.IsValidPixelPosition(iX, iY)

    return iX, iY
end

CGameMode.IsValidPixelPosition = function(iX, iY)
    if tFloor[iX][iY].bBlocked or tFloor[iX][iY].bDefect or (iX == CSnake.iHeadX and iY == CSnake.iHeadY) or tFloor[iX][iY].iPixelID ~= 0 then return false end

    return true
end

CGameMode.EndGame = function(bVictory)
    CGameMode.bVictory = bVictory
    CAudio.StopBackground()

    if bVictory then
        if #tGame.StartPositions == 1 then
            CGameMode.iWinnerID = 1
        else
            --[[
            local iMaxScore = -999
            
            for iPlayerID = 1, #tGame.StartPositions do
                if tPlayerInGame[iPlayerID] and tGameStats.Players[iPlayerID].Score > iMaxScore then
                    CGameMode.iWinnerID = iPlayerID
                    iMaxScore = tGameStats.Players[iPlayerID].Score
                end
            end
            ]]

            CAudio.PlaySync(tGame.StartPositions[CGameMode.iWinnerID].Color)
        end

        CAudio.PlaySync(CAudio.VICTORY)
    else
        CAudio.PlaySync(CAudio.DEFEAT)
    end

    iGameState = GAMESTATE_POSTGAME

    CTimer.New(tConfig.WinDurationMS, function()
        iGameState = GAMESTATE_FINISH
    end)   
end

CGameMode.LoadBlockList = function()
    local iBlockID = 0

    for iX = 1, tGame.Cols do
        for iY = 1, tGame.Rows do
            iBlockID = iBlockID + 1
            CGameMode.tBlockList[iBlockID] = {}
            CGameMode.tBlockList[iBlockID].iX = iX
            CGameMode.tBlockList[iBlockID].iY = iY
        end
    end
end
--//

--SNAKE
CSnake = {}
CSnake.iHeadX = 0
CSnake.iDir = 1
CSnake.iHeadY = 0
CSnake.iLength = 1
CSnake.iDestPixelID = 0
CSnake.tTail = {}
CSnake.iColor = CColors.RED
CSnake.bStepedOn = false
CSnake.tPath = nil
CSnake.iStep = 2

CSnake.Create = function()
    CSnake.iHeadX = math.floor(tGame.Cols/2)
    CSnake.iHeadY = math.floor(tGame.Rows/2)
    CSnake.iLength = tConfig.SnakeLength-1

    for i = 1, CSnake.iLength do
        CSnake.tTail[i] = {}
        CSnake.tTail[i].iX = CSnake.iHeadX + (i)
        CSnake.tTail[i].iY = CSnake.iHeadY

        if tFloor[CSnake.tTail[i].iX] and tFloor[CSnake.tTail[i].iX][CSnake.tTail[i].iY] then
            tFloor[CSnake.tTail[i].iX][CSnake.tTail[i].iY].bBlocked = true
        end
    end
end

CSnake.Start = function()
    CTimer.New(tConfig.SnakeThinkTime, function()
        if iGameState ~= GAMESTATE_GAME then return nil end

        CSnake.Think()
        return tConfig.SnakeThinkTime
    end)
end

CSnake.Think = function()
    if CSnake.iDestPixelID == 0 or CGameMode.tPixels[CSnake.iDestPixelID].iX == nil then
        CSnake.NewDestination()
    end
        local iXPlus, iYPlus = 0, 0
    if CSnake.iDir == 1 then
        iXPlus, iYPlus = -1,0
        if CSnake.iHeadX == 1 then
        if CSnake.CanMove(tGame.Cols-1, 0) then
         	CSnake.Move(tGame.Cols-1,0)
         end
         iXPlus, iYPlus = 0,0
        end
    end	
    if CSnake.iDir == 2 then
        iXPlus, iYPlus = 1,0
        if CSnake.iHeadX == 24 then
        if CSnake.CanMove(-(tGame.Cols-1), 0) then
         CSnake.Move(-(tGame.Cols-1),0)
         end
         iXPlus, iYPlus = 0,0
        end
    end	
    if CSnake.iDir == 3 then
        iXPlus, iYPlus = 0,-1
        if CSnake.iHeadY == 1 then
        if CSnake.CanMove(0, tGame.Rows-1) then
         CSnake.Move(0,tGame.Rows-1)
         end
         iXPlus, iYPlus = 0,0
        end
    end	
    if CSnake.iDir == 4 then
        iXPlus, iYPlus = 0,1
        if CSnake.iHeadY == 15 then
        if CSnake.CanMove(0, -(tGame.Rows-1)) then
         CSnake.Move(0,-(tGame.Rows-1))
         end
         iXPlus, iYPlus = 0,0
        end
    end	
        
    if CSnake.CanMove(iXPlus, iYPlus) then
            CSnake.Move(iXPlus, iYPlus)
    end

    if tFloor[CSnake.iHeadX][CSnake.iHeadY].iPixelID ~= 0 then
        local iSnakePixelID = tFloor[CSnake.iHeadX][CSnake.iHeadY].iPixelID
        if CGameMode.tPixels[iSnakePixelID] and CGameMode.tPixels[iSnakePixelID].iX then 
            CSnake.SnakeCollectPixel(iSnakePixelID)
            CSnake.NewDestination()
        end
    end    
end

CSnake.CanMove = function(iXPlus, iYPlus)
    local iX, iY = CSnake.iHeadX+iXPlus, CSnake.iHeadY+iYPlus

    if not tFloor[iX] or not tFloor[iX][iY] then return false end
    
    

    return true
end

CSnake.Move = function(iXPlus, iYPlus)
    for i = CSnake.iLength, 1, -1 do
        if (CSnake.tTail[i].iX > 0 and i == CSnake.iLength) or (CSnake.tTail[i+1] and CSnake.tTail[i+1].iX == 0 and i == CSnake.iLength -1) then
            if tFloor[CSnake.tTail[i].iX] and tFloor[CSnake.tTail[i].iX][CSnake.tTail[i].iY] then
                tFloor[CSnake.tTail[i].iX][CSnake.tTail[i].iY].bBlocked = false
            end
        end

        local iNextX = CSnake.iHeadX
        local iNextY = CSnake.iHeadY
        if i > 1 then
            iNextX = CSnake.tTail[i-1].iX
            iNextY = CSnake.tTail[i-1].iY
        end

        CSnake.tTail[i].iX = iNextX 
        CSnake.tTail[i].iY = iNextY

        if tFloor[CSnake.tTail[i].iX] and tFloor[CSnake.tTail[i].iX][CSnake.tTail[i].iY] then
            tFloor[CSnake.tTail[i].iX][CSnake.tTail[i].iY].bBlocked = true        
        end
    end    

    CSnake.iHeadX = CSnake.iHeadX + iXPlus
    CSnake.iHeadY = CSnake.iHeadY + iYPlus    
end

CSnake.NewDestination = function()
    CSnake.tPath = nil
    CSnake.iDestPixelID = 0

    local iMaxDist = -1

    for iPixelID = 1, #CGameMode.tPixels do
        if CGameMode.tPixels[iPixelID] and CGameMode.tPixels[iPixelID].iX then
            local iDist = CPath.Dist(CGameMode.tPixels[iPixelID].iX, CGameMode.tPixels[iPixelID].iY, CSnake.iHeadX, CSnake.iHeadY)

            if iDist > iMaxDist then
                iMaxDist = iDist
                CSnake.iDestPixelID = iPixelID
            end
        end
    end
end

CSnake.GetPath = function(bStuck)
    CSnake.iStep = 2

    return CPath.Path(
        {iX = CSnake.iHeadX, iY = CSnake.iHeadY}, 
        {iX = CGameMode.tPixels[CSnake.iDestPixelID].iX, iY = CGameMode.tPixels[CSnake.iDestPixelID].iY}, 
        CGameMode.tBlockList,
        bStuck)    
end

CSnake.SnakeCollectPixel = function(iPixelID)
    local iPlayerID = CGameMode.tPixels[iPixelID].iPlayerID
    CGameMode.tPixels[iPixelID] = {}
    CGameMode.PlacePixelForPlayer(iPlayerID)    

    CAudio.PlayAsync(CAudio.MISCLICK)

    CSnake.iLength = CSnake.iLength + 1
    CSnake.tTail[CSnake.iLength] = {}
    CSnake.tTail[CSnake.iLength].iX = 0
    CSnake.tTail[CSnake.iLength].iY = 0

    CSnake.DamagePlayer()
end

CSnake.PlayerStepOnSnake = function()
    if CSnake.bStepedOn then return; end
    CSnake.bStepedOn = true

    CAudio.PlayAsync(CAudio.MISCLICK)

    if tConfig.SnakeDamagePlayerOnStep then
        CSnake.DamagePlayer()
    end

    CSnake.SnakePulse()
end

CSnake.DamagePlayer = function()
    tGameStats.Players[6].Score = tGameStats.Players[6].Score + 1
    if tGameStats.Players[6].Score >= tGameStats.TargetScore then
        CGameMode.EndGame(false)
    end 
end

CSnake.SnakePulse = function()
    local iIter = 0

    CTimer.New(CPaint.ANIMATION_DELAY, function()
        iIter = iIter + 1

        if CSnake.iColor == CColors.RED then
            CSnake.iColor = CColors.MAGENTA
        else
            CSnake.iColor = CColors.RED
        end

        if iIter < 6 then
            return CPaint.ANIMATION_DELAY
        end

        CSnake.bStepedOn = false
        return nil
    end)
end
--//

--PAINT
CPaint = {}
CPaint.ANIMATION_DELAY = 100

CPaint.PlayerZone = function(iPlayerID, iBright)
    SetRectColorBright(tGame.StartPositions[iPlayerID].X, 
        tGame.StartPositions[iPlayerID].Y, 
        tGame.StartPositionSizeX-1, 
        tGame.StartPositionSizeY-1, 
        tGame.StartPositions[iPlayerID].Color, 
        iBright)
end

CPaint.Pixels = function()
    for iPixelID = 1, #CGameMode.tPixels do
        if CGameMode.tPixels[iPixelID] and CGameMode.tPixels[iPixelID].iX  then
            tFloor[CGameMode.tPixels[iPixelID].iX][CGameMode.tPixels[iPixelID].iY].iColor = tGame.StartPositions[CGameMode.tPixels[iPixelID].iPlayerID].Color
            tFloor[CGameMode.tPixels[iPixelID].iX][CGameMode.tPixels[iPixelID].iY].iBright = tConfig.Bright
        end
    end
end

CPaint.Snake = function()
    for i = 1, #CSnake.tTail do
        if CSnake.tTail[i] and CSnake.tTail[i].iX > 0 then
            if tFloor[CSnake.tTail[i].iX] and tFloor[CSnake.tTail[i].iX][CSnake.tTail[i].iY] then
                tFloor[CSnake.tTail[i].iX][CSnake.tTail[i].iY].iColor = CSnake.iColor
                tFloor[CSnake.tTail[i].iX][CSnake.tTail[i].iY].iBright = tConfig.Bright-1
            end
        end    
    end

    tFloor[CSnake.iHeadX][CSnake.iHeadY].iColor = CSnake.iColor
    tFloor[CSnake.iHeadX][CSnake.iHeadY].iBright = tConfig.Bright+1
end

CPaint.ResetAnimation = function()
    for iX = 1, tGame.Cols do
        for iY = 1, tGame.Rows do
            tFloor[iX][iY].bAnimated = false
        end
    end
end

CPaint.AnimatePixelFlicker = function(iX, iY, iFlickerCount, iColor)
    if tFloor[iX][iY].bAnimated then return; end
    tFloor[iX][iY].bAnimated = true

    local iCount = 0
    CTimer.New(CPaint.ANIMATION_DELAY*3, function()
        if not tFloor[iX][iY].bAnimated then return; end

        if tFloor[iX][iY].iColor == iColor then
            tFloor[iX][iY].iBright = tConfig.Bright + 1
            tFloor[iX][iY].iColor = CColors.MAGENTA
            iCount = iCount + 1
        else
            tFloor[iX][iY].iBright = tConfig.Bright
            tFloor[iX][iY].iColor = iColor
            iCount = iCount + 1
        end
        
        if iCount <= iFlickerCount then
            return CPaint.ANIMATION_DELAY*3
        end

        tFloor[iX][iY].iBright = tConfig.Bright
        tFloor[iX][iY].iColor = iColor
        tFloor[iX][iY].bAnimated = false

        return nil
    end)
end
--//

--PATHFINDING
CPath = {}
CPath.Dist = function(iX1, iY1, iX2, iY2)
    return math.sqrt(math.pow(iX2 - iX1, 2) + math.pow(iY2 - iY1, 2))
end

--//

--TIMER класс отвечает за таймеры, очень полезная штука. можно вернуть время нового таймера с тем же колбеком
CTimer = {}
CTimer.tTimers = {}

CTimer.New = function(iSetTime, fCallback)
    CTimer.tTimers[#CTimer.tTimers+1] = {iTime = iSetTime, fCallback = fCallback}
end

-- просчёт таймеров каждый тик
CTimer.CountTimers = function(iTimePassed)
    for i = 1, #CTimer.tTimers do
        if CTimer.tTimers[i] ~= nil then
            CTimer.tTimers[i].iTime = CTimer.tTimers[i].iTime - iTimePassed

            if CTimer.tTimers[i].iTime <= 0 then
                iNewTime = CTimer.tTimers[i].fCallback()
                if iNewTime and iNewTime ~= nil then -- если в return было число то создаём новый таймер с тем же колбеком
                    iNewTime = iNewTime + CTimer.tTimers[i].iTime
                    CTimer.New(iNewTime, CTimer.tTimers[i].fCallback)
                end

                CTimer.tTimers[i] = nil
            end
        end
    end
end
--//

--UTIL прочие утилиты
function CheckPositionClick(tStart, iSizeX, iSizeY)
    for iX = tStart.X, tStart.X + iSizeX - 1 do
        for iY = tStart.Y, tStart.Y + iSizeY - 1 do
            if tFloor[iX] and tFloor[iX][iY] then
                if tFloor[iX][iY].bClick then
                    return true
                end 
            end
        end
    end

    return false
end

function SetPositionColorBright(tStart, iSize, iColor, iBright)
    for i = 0, iSize * iSize - 1 do
        local iX = tStart.X + i % iSize
        local iY = tStart.Y + math.floor(i / iSize)

        if not (iX < 1 or iX > tGame.Cols or iY < 1 or iY > tGame.Rows) then     
            tFloor[iX][iY].iColor = iColor
            tFloor[iX][iY].iBright = iBright            
        end
    end
end

function SetRectColorBright(iX, iY, iSizeX, iSizeY, iColor, iBright)
    for i = iX, iX + iSizeX do
        for j = iY, iY + iSizeY do
            if not (i < 1 or j > tGame.Cols or j < 1 or j > tGame.Rows) and not tFloor[i][j].bAnimated then     
                tFloor[i][j].iColor = iColor
                tFloor[i][j].iBright = iBright            
            end            
        end
    end
end

function RectIntersects(iX1, iY1, iSize1, iX2, iY2, iSize2)
    if iSize1 == 0 or iSize2 == 0 then return false; end

    if iX1 > iX2+iSize2-1 or iX2 > iX1+iSize1-1 then return false; end

    if iY1+iSize1-1 < iY2 or iY2+iSize2-1 < iY1 then return false; end

    return true
end

function SetGlobalColorBright(iColor, iBright)
    for iX = 1, tGame.Cols do
        for iY = 1, tGame.Rows do
            tFloor[iX][iY].iColor = iColor
            tFloor[iX][iY].iBright = iBright
        end
    end

    for i, tButton in pairs(tButtons) do
        tButtons[i].iColor = iColor
        tButtons[i].iBright = iBright
    end
end

function SetAllButtonColorBright(iColor, iBright)
    for i, tButton in pairs(tButtons) do
        if not tButtons[i].bDefect then
            tButtons[i].iColor = iColor
            tButtons[i].iBright = iBright
        end
    end
end
--//


--//
function GetStats()
    return tGameStats
end

function PauseGame()
    bGamePaused = true
end

function ResumeGame()
    bGamePaused = false
end

function PixelClick(click)
    tFloor[click.X][click.Y].bClick = click.Click
    tFloor[click.X][click.Y].iWeight = click.Weight


    if click.Click and iGameState == GAMESTATE_GAME then
        if tFloor[click.X][click.Y].bBlocked or (click.X == CSnake.iHeadX and click.Y == CSnake.iHeadY) then
            CSnake.PlayerStepOnSnake()
        elseif tFloor[click.X][click.Y].iPixelID ~= 0 then
            CGameMode.PlayerClickPixel(tFloor[click.X][click.Y].iPixelID)
        end
    end
end

function DefectPixel(defect)
    tFloor[defect.X][defect.Y].bDefect = defect.Defect

    if defect.Defect and tFloor[defect.X][defect.Y].iPixelID ~= 0 then
        CGameMode.PlayerClickPixel(tFloor[defect.X][defect.Y].iPixelID)
    end
end

function ButtonClick(click)
    if tButtons[click.Button] ~= nil then
    	tButtons[click.Button].bClick = click.Click
    end

    if click.Click then
        bAnyButtonClick = true
    end
    
    if click.GamepadLeftClick and CSnake.iDir ~= 2 then
       CSnake.iDir = 1
    end
    
    if click.GamepadRightClick and CSnake.iDir ~= 1 then
       CSnake.iDir = 2
    end
    if click.GamepadUpClick and CSnake.iDir ~= 4 then
       CSnake.iDir = 3
    end
    if click.GamepadDownClick and CSnake.iDir ~= 3 then
       CSnake.iDir = 4
    end
end

function DefectButton(defect)
    if tButtons[defect.Button] == nil then return end
    tButtons[defect.Button].bDefect = defect.Defect

    if defect.Defect then
        tButtons[defect.Button].iColor = CColors.NONE
        tButtons[defect.Button].iBright = CColors.BRIGHT0
    end    
end
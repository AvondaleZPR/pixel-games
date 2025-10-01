--[[
    Название: Аэрохоккей
    Автор: Avondale, дискорд - avonda
    Описание механики: в общих словах, что происходит в механике
    Идеи по доработке: то, что может улучшить игру, но не было реализовано здесь
]]
math.randomseed(os.time())
require("avonlib")

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
    CurrentLives = 0,
    TotalLives = 0,
    Players = { -- максимум 6 игроков
        { Score = 0, Lives = 0, Color = CColors.RED },
        { Score = 0, Lives = 0, Color = CColors.BLUE },
        { Score = 0, Lives = 0, Color = CColors.NONE },
        { Score = 0, Lives = 0, Color = CColors.NONE },
        { Score = 0, Lives = 0, Color = CColors.NONE },
        { Score = 0, Lives = 0, Color = CColors.NONE },
    },
    TargetScore = 0,
    StageNum = 0,
    TotalStages = 0,
    TargetColor = CColors.NONE,
    ScoreboardVariant = 6,
}

local tGameResults = {
    Won = false,
    AfterDelay = false,
    PlayersCount = 0,
    Score = 0,
    Color = CColors.NONE,
}

local tFloor = {} 
local tButtons = {}

local tFloorStruct = { 
    iColor = CColors.NONE,
    iBright = CColors.BRIGHT0,
    bClick = false,
    bDefect = false,
    iWeight = 0,
    iTime = 0,
}
local tButtonStruct = { 
    bClick = false,
    bDefect = false,
}

local tPlayerInGame = {}

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

    iPrevTickTime = CTime.unix()

    if AL.RoomHasNFZ(tGame) then
        AL.LoadNFZInfo()
    end

    tGame.iMinX = 1
    tGame.iMinY = 1
    tGame.iMaxX = tGame.Cols
    tGame.iMaxY = tGame.Rows
    if AL.NFZ.bLoaded then
        tGame.iMinX = AL.NFZ.iMinX
        tGame.iMinY = AL.NFZ.iMinY
        tGame.iMaxX = AL.NFZ.iMaxX
        tGame.iMaxY = AL.NFZ.iMaxY
    end
    tGame.CenterX = math.floor((tGame.iMaxX-tGame.iMinX+1)/2)
    tGame.CenterY = math.ceil((tGame.iMaxY-tGame.iMinY+1)/2)

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

        if not tGameResults.AfterDelay then
            tGameResults.AfterDelay = true
            return tGameResults
        end
    end

    if iGameState == GAMESTATE_FINISH then
        tGameResults.AfterDelay = false
        return tGameResults
    end     

    AL.CountTimers((CTime.unix() - iPrevTickTime) * 1000)
    iPrevTickTime = CTime.unix()
end

function GameSetupTick()
    SetGlobalColorBright(CColors.NONE, CColors.BRIGHT0)
    CPlayerControls.PaintField()
    CPhysics.Paint()

    local iPlayersReady = 0
    for iPlayerID = 1, 2 do
        if CheckRectClick(CPlayerControls.tZones[iPlayerID].iX, CPlayerControls.tZones[iPlayerID].iY, CPlayerControls.tZones[iPlayerID].iSizeX, CPlayerControls.tZones[iPlayerID].iSizeY) then
            tPlayerInGame[iPlayerID] = true
            iPlayersReady = iPlayersReady + 1
        else
            tPlayerInGame[iPlayerID] = false
        end
    end

    if iPlayersReady == 2 then
        iGameState = GAMESTATE_GAME
        CGameMode.StartCountDown(5)
        CGameMode.GameLoop()
    end
end

function GameTick()
    SetGlobalColorBright(CColors.NONE, CColors.BRIGHT0)    
    CPlayerControls.PaintField()
    CPhysics.Paint()
end

function PostGameTick()
    
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
CGameMode.bCanAutoStart = false
CGameMode.bGameStarted = false

CGameMode.tPlayerColors = {}
CGameMode.tPlayerColors[1] = CColors.RED
CGameMode.tPlayerColors[2] = CColors.BLUE

CGameMode.InitGameMode = function()
    tGameStats.TargetScore = tConfig.TargetScore

    CPlayerControls.InitField()

    CGameMode.PO_Player1 = CPhysics.NewPhysicsObject(tGame.iMinX + 5, tGame.CenterY, tConfig.DiscSize, CPhysics.TYPE_PLAYER, CGameMode.tPlayerColors[1], 1)
    CGameMode.PO_Player2 = CPhysics.NewPhysicsObject(tGame.iMaxX - 5, tGame.CenterY, tConfig.DiscSize, CPhysics.TYPE_PLAYER, CGameMode.tPlayerColors[2], 2)
    CGameMode.PO_BALL = CPhysics.NewPhysicsObject(tGame.CenterX, tGame.CenterY, 0, CPhysics.TYPE_BALL, CColors.GREEN, 0)

    CGameMode.PO_Gate1 = CPhysics.NewPhysicsObject(tGame.iMinX, tGame.CenterY-math.floor(tConfig.GateSize/2), tConfig.GateSize-1, CPhysics.TYPE_GOAL, CGameMode.tPlayerColors[1], 1)
    CGameMode.PO_Gate2 = CPhysics.NewPhysicsObject(tGame.iMaxX, tGame.CenterY-math.floor(tConfig.GateSize/2), tConfig.GateSize-1, CPhysics.TYPE_GOAL, CGameMode.tPlayerColors[2], 2)
end

CGameMode.Announcer = function()
    --voice gamename rules

    AL.NewTimer(1000, function()
        CGameMode.bCanAutoStart = true
    end)    
end

CGameMode.StartCountDown = function(iCountDownTime)
    CGameMode.iCountdown = iCountDownTime

    AL.NewTimer(1000, function()
        CAudio.ResetSync()
        tGameStats.StageLeftDuration = CGameMode.iCountdown

        if CGameMode.iCountdown <= 0 then
            if not CGameMode.bGameStarted then
                CGameMode.StartGame()
            end

            CGameMode.StartRound()

            return nil
        else
            CAudio.PlayLeftAudio(CGameMode.iCountdown)
            CGameMode.iCountdown = CGameMode.iCountdown - 1

            return 1000
        end
    end)
end

CGameMode.StartGame = function()
    CGameMode.bGameStarted = true
    CAudio.PlayVoicesSync(CAudio.START_GAME)
    CAudio.PlayRandomBackground()
end

CGameMode.EndGame = function(iWinnerID)
    CGameMode.iWinnerID = iWinnerID

    tGameResults.Color = CGameMode.tPlayerColors[iWinnerID]
    tGameResults.Won = true

    CAudio.StopBackground()
    CAudio.PlaySystemSyncFromScratch(CAudio.GAME_SUCCESS)
    CAudio.PlaySyncColorSound(CGameMode.tPlayerColors[iWinnerID])
    CAudio.PlayVoicesSync(CAudio.VICTORY)    

    iGameState = GAMESTATE_POSTGAME

    SetGlobalColorBright(CGameMode.tPlayerColors[iWinnerID], tConfig.Bright)

    AL.NewTimer(10000, function()
        iGameState = GAMESTATE_FINISH
    end)
end

CGameMode.StartRound = function()
    CPhysics.tObjects[CGameMode.PO_BALL].iVelX = math.random(math.floor(CPhysics.MAX_VELOCITY/8), math.floor(CPhysics.MAX_VELOCITY/5))
    CPhysics.tObjects[CGameMode.PO_BALL].iVelY = math.random(math.floor(CPhysics.MAX_VELOCITY/8), math.floor(CPhysics.MAX_VELOCITY/5))
    if math.random(1,2) == 2 then CPhysics.tObjects[CGameMode.PO_BALL].iVelX = -CPhysics.tObjects[CGameMode.PO_BALL].iVelX; end
    if math.random(1,2) == 2 then CPhysics.tObjects[CGameMode.PO_BALL].iVelY = -CPhysics.tObjects[CGameMode.PO_BALL].iVelY; end
end

CGameMode.GameLoop = function()
    AL.NewTimer(100, function()
        if iGameState ~= GAMESTATE_GAME then return nil; end
        
        CPlayerControls.Tick()
        return 100
    end)    
end

CGameMode.ScoreGoal = function(iPlayerID)
    local iWinnerID = 1
    if iPlayerID == 1 then iWinnerID = 2; end

    CPhysics.tObjects[CGameMode.PO_BALL].iVelX = 0
    CPhysics.tObjects[CGameMode.PO_BALL].iVelY = 0

    CPhysics.tObjects[CGameMode.PO_BALL].iX = tGame.CenterX
    CPhysics.tObjects[CGameMode.PO_BALL].iY = tGame.CenterY

    CAudio.PlaySystemSync(CAudio.CLICK)

    tGameStats.Players[iWinnerID].Score = tGameStats.Players[iWinnerID].Score + 1
    if tGameStats.Players[iWinnerID].Score == tGameStats.TargetScore then
        CGameMode.EndGame(iWinnerID)
        return; 
    end

    CGameMode.StartCountDown(5)
end
--//

--controls
CPlayerControls = {}
CPlayerControls.tZones = {}
CPlayerControls.iMiddleSize = 0
CPlayerControls.iMiddleX = 0

CPlayerControls.InitField = function()
    CPlayerControls.iMiddleX = tGame.CenterX
    CPlayerControls.tZones[1] = {}
    CPlayerControls.tZones[1].iX = tGame.iMinX
    CPlayerControls.tZones[1].iY = tGame.iMinY
    CPlayerControls.tZones[1].iSizeX = tGame.CenterX-1 - math.floor(CPlayerControls.iMiddleSize/2)
    CPlayerControls.tZones[1].iSizeY = tGame.iMaxY
    CPlayerControls.tZones[1].iTargetTime = CTime.unix()

    CPlayerControls.tZones[2] = {}
    CPlayerControls.tZones[2].iX = tGame.CenterX+1 + math.floor(CPlayerControls.iMiddleSize/2)
    CPlayerControls.tZones[2].iY = tGame.iMinY
    CPlayerControls.tZones[2].iSizeX = tGame.iMaxX - 1 - CPlayerControls.tZones[1].iX
    CPlayerControls.tZones[2].iSizeY = tGame.iMaxY
    CPlayerControls.tZones[2].iTargetTime = CTime.unix()
end

CPlayerControls.Tick = function()
    for iZone = 1, #CPlayerControls.tZones do
        for iX = CPlayerControls.tZones[iZone].iX, CPlayerControls.tZones[iZone].iX + CPlayerControls.tZones[iZone].iSizeX-1 do
            for iY = CPlayerControls.tZones[iZone].iY, CPlayerControls.tZones[iZone].iY + CPlayerControls.tZones[iZone].iSizeY-1 do
                if tFloor[iX] and tFloor[iX][iY] and not tFloor[iX][iY].bDefect then
                    if tFloor[iX][iY].iTime > CPlayerControls.tZones[iZone].iTargetTime then
                        CPlayerControls.tZones[iZone].iTargetTime = tFloor[iX][iY].iTime
                        CPhysics.tObjects[iZone].iVelX = (iX - CPhysics.tObjects[iZone].iX)*tGame.Rows
                        CPhysics.tObjects[iZone].iVelY = (iY - CPhysics.tObjects[iZone].iY)*tGame.Cols
                    end
                end
            end
        end
    end 
end

CPlayerControls.PaintField = function()
    for iX = tGame.CenterX-CPlayerControls.iMiddleSize, tGame.CenterX+CPlayerControls.iMiddleSize do
        for iY = 1, tGame.Rows do
            tFloor[iX][iY].iColor = CColors.WHITE
            tFloor[iX][iY].iBright = tConfig.Bright-1
        end
    end

    if iGameState == GAMESTATE_SETUP then
        for iZone = 1, #CPlayerControls.tZones do
            local iBright = tConfig.Bright-2
            if not tPlayerInGame[iZone] then iBright = 1; end
            SetRectColorBright(CPlayerControls.tZones[iZone].iX, CPlayerControls.tZones[iZone].iY, CPlayerControls.tZones[iZone].iSizeX, CPlayerControls.tZones[iZone].iSizeY, CGameMode.tPlayerColors[iZone], iBright)
        end
    end
end
--//

--physics objects
CPhysics = {}
CPhysics.tObjects = {}

CPhysics.TYPE_PLAYER = 1
CPhysics.TYPE_BALL = 2
CPhysics.TYPE_GOAL = 3

CPhysics.MAX_VELOCITY = 250

CPhysics.NewPhysicsObject = function(iX, iY, iSize, iPhysicsType, iColor, iPlayerID)
    local iObjectID = #CPhysics.tObjects+1
    CPhysics.tObjects[iObjectID] = {}
    CPhysics.tObjects[iObjectID].iX = iX
    CPhysics.tObjects[iObjectID].iY = iY
    CPhysics.tObjects[iObjectID].iSize = iSize
    CPhysics.tObjects[iObjectID].iPhysicsType = iPhysicsType
    CPhysics.tObjects[iObjectID].iColor = iColor
    CPhysics.tObjects[iObjectID].iVelX = 0
    CPhysics.tObjects[iObjectID].iVelY = 0
    CPhysics.tObjects[iObjectID].iPlayerID = iPlayerID or 0

    if iPhysicsType == CPhysics.TYPE_PLAYER or iPhysicsType == CPhysics.TYPE_BALL then
        AL.NewTimer(100, function()
            if iGameState > GAMESTATE_GAME then return nil; end
            if CPhysics.tObjects[iObjectID].iVelX == 0 then return 100; end

            if CPhysics.tObjects[iObjectID].iVelX > CPhysics.MAX_VELOCITY then CPhysics.tObjects[iObjectID].iVelX = CPhysics.MAX_VELOCITY; end
            if CPhysics.tObjects[iObjectID].iVelX < -CPhysics.MAX_VELOCITY then CPhysics.tObjects[iObjectID].iVelX = -CPhysics.MAX_VELOCITY; end

            local iXPlus = -1
            if CPhysics.tObjects[iObjectID].iVelX > 0 then
                iXPlus = 1
            end

            local bValidMove = CPhysics.CalculateObjectMove(iObjectID, iXPlus, 0)
            if not bValidMove then
                if CPhysics.tObjects[iObjectID].iPhysicsType == CPhysics.TYPE_BALL then
                    CAudio.PlaySystemAsync("dodge/ball-bounce.mp3")
                end

                return 25
            end

            CPhysics.tObjects[iObjectID].iVelX = CPhysics.tObjects[iObjectID].iVelX*0.95

            return (CPhysics.MAX_VELOCITY + 50) - math.abs(CPhysics.tObjects[iObjectID].iVelX)
        end)

        AL.NewTimer(100, function()
            if iGameState > GAMESTATE_GAME then return nil; end
            if CPhysics.tObjects[iObjectID].iVelY == 0 then return 100; end

            if CPhysics.tObjects[iObjectID].iVelY > CPhysics.MAX_VELOCITY then CPhysics.tObjects[iObjectID].iVelY = CPhysics.MAX_VELOCITY; end
            if CPhysics.tObjects[iObjectID].iVelY < -CPhysics.MAX_VELOCITY then CPhysics.tObjects[iObjectID].iVelY = -CPhysics.MAX_VELOCITY; end

            local iYPlus = -1
            if CPhysics.tObjects[iObjectID].iVelY > 0 then
                iYPlus = 1
            end

            local bValidMove = CPhysics.CalculateObjectMove(iObjectID, 0, iYPlus)
            if not bValidMove then
                if CPhysics.tObjects[iObjectID].iPhysicsType == CPhysics.TYPE_BALL then
                    CAudio.PlaySystemAsync("dodge/ball-bounce.mp3")
                end

                return 25
            end

            CPhysics.tObjects[iObjectID].iVelY = CPhysics.tObjects[iObjectID].iVelY*0.95

            return (CPhysics.MAX_VELOCITY + 50) - math.abs(CPhysics.tObjects[iObjectID].iVelY)
        end)        
    end

    return iObjectID
end

CPhysics.CalculateObjectMove = function(iObjectID, iXPlus, iYPlus)
    if iXPlus == 0 and iYPlus == 0 then return true; end

    local iNewX = CPhysics.tObjects[iObjectID].iX + iXPlus
    local iNewY = CPhysics.tObjects[iObjectID].iY + iYPlus

    if iXPlus ~= 0 then
        if iNewX < 1 or iNewX > tGame.Cols then
            if CPhysics.tObjects[iObjectID].iPhysicsType == CPhysics.TYPE_BALL then
                CPhysics.ReverseObjectVelocity(iObjectID, true)
            end

            return false
        end
    else
        if iNewY < 1 or iNewY > tGame.Rows then
            if CPhysics.tObjects[iObjectID].iPhysicsType == CPhysics.TYPE_BALL then
                CPhysics.ReverseObjectVelocity(iObjectID, false)
            end

            return false
        end
    end

    if CPhysics.tObjects[iObjectID].iPhysicsType == CPhysics.TYPE_PLAYER then
        if (iNewX < CPlayerControls.tZones[iObjectID].iX or iNewX > CPlayerControls.tZones[iObjectID].iX+CPlayerControls.tZones[iObjectID].iSizeX-1) then
            CPhysics.tObjects[iObjectID].iVelX = 0
            return false 
        elseif (iNewY < CPlayerControls.tZones[iObjectID].iY or iNewY > CPlayerControls.tZones[iObjectID].iY+CPlayerControls.tZones[iObjectID].iSizeY-1) then
            CPhysics.tObjects[iObjectID].iVelY = 0
            return false
        end
    end

    if CPhysics.tObjects[iObjectID].iPhysicsType == CPhysics.TYPE_BALL then
        for iColID = 1, #CPhysics.tObjects do
            if CPhysics.tObjects[iColID].iPhysicsType == CPhysics.TYPE_PLAYER then
                if CPhysics.CircleCollisionCheck(CPhysics.tObjects[iColID].iX, CPhysics.tObjects[iColID].iY, CPhysics.tObjects[iColID].iSize, iNewX, iNewY, CPhysics.tObjects[iObjectID].iSize) then
                    CLog.print("coll")
                    if iXPlus ~= 0 then
                        CPhysics.ReverseObjectVelocity(iObjectID, true)
                        CPhysics.tObjects[iObjectID].iVelX = CPhysics.tObjects[iObjectID].iVelX + math.floor(CPhysics.tObjects[iColID].iVelX*1.25)
                    else
                        CPhysics.ReverseObjectVelocity(iObjectID, false)
                        CPhysics.tObjects[iObjectID].iVelY = CPhysics.tObjects[iObjectID].iVelY + math.floor(CPhysics.tObjects[iColID].iVelY*1.25)
                    end

                    return false
                end
            end
        end

        if iNewX == 1 or iNewX == tGame.Cols then
            for iGateID = 1, #CPhysics.tObjects do
                if CPhysics.tObjects[iGateID].iPhysicsType == CPhysics.TYPE_GOAL then
                    if iNewX == CPhysics.tObjects[iGateID].iX then
                        if iNewY >= CPhysics.tObjects[iGateID].iY and iNewY <= (CPhysics.tObjects[iGateID].iY + CPhysics.tObjects[iGateID].iSize-1) then
                            CGameMode.ScoreGoal(CPhysics.tObjects[iGateID].iPlayerID)
                            return true
                        end
                    end
                end
            end
        end
    end

    CPhysics.tObjects[iObjectID].iX = iNewX
    CPhysics.tObjects[iObjectID].iY = iNewY
    return true
end

CPhysics.ReverseObjectVelocity = function(iObjectID, bX)
    if bX then
        CPhysics.tObjects[iObjectID].iVelX = (-CPhysics.tObjects[iObjectID].iVelX)*1.15 
    else
        CPhysics.tObjects[iObjectID].iVelY = (-CPhysics.tObjects[iObjectID].iVelY)*1.15 
    end
end

CPhysics.Paint = function()
    local paintPixel = function(iX, iY, iColor, iBright)
        if tFloor[iX] and tFloor[iX][iY] then
            tFloor[iX][iY].iColor = iColor
            tFloor[iX][iY].iBright = tConfig.Bright
        end
    end

    for iObjectID = 1, #CPhysics.tObjects do
        if CPhysics.tObjects[iObjectID] then
            paintPixel(CPhysics.tObjects[iObjectID].iX, CPhysics.tObjects[iObjectID].iY, CPhysics.tObjects[iObjectID].iColor)
            if CPhysics.tObjects[iObjectID].iPhysicsType == CPhysics.TYPE_PLAYER then
                for iSize = 1, CPhysics.tObjects[iObjectID].iSize do
                    paintPixel(CPhysics.tObjects[iObjectID].iX + iSize, CPhysics.tObjects[iObjectID].iY, CPhysics.tObjects[iObjectID].iColor)
                    paintPixel(CPhysics.tObjects[iObjectID].iX - iSize, CPhysics.tObjects[iObjectID].iY, CPhysics.tObjects[iObjectID].iColor)
                    paintPixel(CPhysics.tObjects[iObjectID].iX, CPhysics.tObjects[iObjectID].iY + iSize, CPhysics.tObjects[iObjectID].iColor)
                    paintPixel(CPhysics.tObjects[iObjectID].iX, CPhysics.tObjects[iObjectID].iY - iSize, CPhysics.tObjects[iObjectID].iColor)

                    if iSize ~= CPhysics.tObjects[iObjectID].iSize then
                        paintPixel(CPhysics.tObjects[iObjectID].iX + iSize, CPhysics.tObjects[iObjectID].iY + iSize, CPhysics.tObjects[iObjectID].iColor)
                        paintPixel(CPhysics.tObjects[iObjectID].iX - iSize, CPhysics.tObjects[iObjectID].iY - iSize, CPhysics.tObjects[iObjectID].iColor)
                        paintPixel(CPhysics.tObjects[iObjectID].iX - iSize, CPhysics.tObjects[iObjectID].iY + iSize, CPhysics.tObjects[iObjectID].iColor)
                        paintPixel(CPhysics.tObjects[iObjectID].iX + iSize, CPhysics.tObjects[iObjectID].iY - iSize, CPhysics.tObjects[iObjectID].iColor)
                    end
                end
            elseif CPhysics.tObjects[iObjectID].iPhysicsType == CPhysics.TYPE_GOAL then
                for iSize = 1, CPhysics.tObjects[iObjectID].iSize do
                    paintPixel(CPhysics.tObjects[iObjectID].iX, CPhysics.tObjects[iObjectID].iY + iSize, CPhysics.tObjects[iObjectID].iColor)
                end
            end
        end
    end
end

CPhysics.CircleCollisionCheck = function(iC1X, iC1Y, iC1R, iC2X, iC2Y, iC2R)
    return math.sqrt((iC2X - iC1X)^2 + (iC2Y - iC1Y)^2) <= iC1R + iC2R
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
    for i = iX, iX + iSizeX-1 do
        for j = iY, iY + iSizeY-1 do
            if not (i < 1 or i > tGame.Cols or j < 1 or j > tGame.Rows) and not tFloor[i][j].bAnimated then     
                tFloor[i][j].iColor = iColor
                tFloor[i][j].iBright = iBright            
            end            
        end
    end
end

function CheckRectClick(iX, iY, iSizeX, iSizeY)
    for i = iX, iX + iSizeX-1 do
        for j = iY, iY + iSizeY-1 do
            if not (i < 1 or i > tGame.Cols or j < 1 or j > tGame.Rows) then
                if not tFloor[i][j].bDefect and tFloor[i][j].bClick then return true; end       
            end
        end
    end

    return false
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

function SetAllButtonColorBright(iColor, iBright, bCheckDefect)
    for i, tButton in pairs(tButtons) do
        if not bCheckDefect or not tButtons[i].bDefect then
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
	iPrevTickTime = CTime.unix()
end

function PixelClick(click)
    if tFloor[click.X] and tFloor[click.X][click.Y] then
        if bGamePaused then
            tFloor[click.X][click.Y].bClick = false
            return;
        end

        if iGameState == GAMESTATE_SETUP then
            if click.Click then
                tFloor[click.X][click.Y].bClick = true
                tFloor[click.X][click.Y].bHold = false
            elseif not tFloor[click.X][click.Y].bHold then
                tFloor[click.X][click.Y].bHold = true
                AL.NewTimer(1000, function()
                    if tFloor[click.X][click.Y].bHold then
                        tFloor[click.X][click.Y].bClick = false
                    end
                end)
            end
            tFloor[click.X][click.Y].iWeight = click.Weight

            return
        end

        tFloor[click.X][click.Y].bClick = click.Click
        tFloor[click.X][click.Y].iWeight = click.Weight
        tFloor[click.X][click.Y].iTime = CTime.unix()
    end
end

function DefectPixel(defect)
    if tFloor[defect.X] and tFloor[defect.X][defect.Y] then
        tFloor[defect.X][defect.Y].bDefect = defect.Defect
    end
end

function ButtonClick(click)
    if tButtons[click.Button] == nil or bGamePaused or tButtons[click.Button].bDefect then return end
    tButtons[click.Button].bClick = click.Click
end

function DefectButton(defect)
    if tButtons[defect.Button] == nil then return end
    tButtons[defect.Button].bDefect = defect.Defect

    if defect.Defect then
        tButtons[defect.Button].iColor = CColors.NONE
        tButtons[defect.Button].iBright = CColors.BRIGHT0
    end    
end
#INCLUDE "totvs.CH"
#INCLUDE "restful.CH"
#INCLUDE "FWMVCDEF.CH"
#INCLUDE "rwmake.ch"
#INCLUDE "topconn.ch"
#INCLUDE "parmtype.ch"
#INCLUDE "protheus.CH"

WSRESTFUL PRODCHECK DESCRIPTION "API PARA VALIDAR PRODUTOS E PARA ENVIAR PEDIDOS DE COMPRA"
    WSMETHOD POST seekProdutos DESCRIPTION "Valida uma lista de produtos" WSSYNTAX "/api/seekProdutos" PATH "/api/seekProdutos" PRODUCES APPLICATION_JSON
    WSMETHOD POST createPedidoCompra DESCRIPTION "Cria Pedido de Compra no Protheus" WSSYNTAX "/api/createPedidoCompra" PATH "/api/createPedidoCompra" PRODUCES APPLICATION_JSON
END WSRESTFUL

WSMETHOD POST seekProdutos WSRECEIVE NULLPARAM WSRESTFUL PRODCHECK
    Local lRet      := .T.
    Local cBody     := Self:GetContent()
    Local oJsonBody := JsonObject():New()
    Local oResp     := JsonObject():New()
    Local aCodes    := {}
    Local aResults  := {}
    Local oItem
    Local nX, cCode

    If Empty(cBody)
        SetRestFault(400, "Body vazio")
        Return .F.
    EndIf

    oJsonBody:FromJson(cBody)
    
    If ValType(oJsonBody:Get("codes")) == "A"
        aCodes := oJsonBody:Get("codes")
        
        DbSelectArea("SB1")
        SB1->(DbSetOrder(1)) 

        For nX := 1 To Len(aCodes)
            cCode := AllTrim(aCodes[nX])
            oItem := JsonObject():New()
            oItem:Set("code", cCode)

            If SB1->(DbSeek(xFilial("SB1") + cCode))
                oItem:Set("found", .T.)
                oItem:Set("desc", AllTrim(SB1->B1_DESC))
            Else
                oItem:Set("found", .F.)
                oItem:Set("desc", "")
            EndIf
            
            AAdd(aResults, oItem)
        Next
    EndIf

    oResp:Set("results", aResults)
    Self:SetResponse(EncodeUTF8(oResp:ToJson()))

Return lRet

WSMETHOD POST createPedidoCompra WSRECEIVE NULLPARAM WSRESTFUL PRODCHECK
    RpcClearEnv()
    RpcSetEnv("05", "0501", NIL, NIL, "COM", NIL, {"SC7"})
    ProcessarPedidoCompra(Self)
    RpcClearEnv()
RETURN .T.

Static Function ProcessarPedidoCompra(Self)
    Local aArea         := GetArea()
    Local aCabec        := {}
    Local aItens        := {}
    Local aItem         := {}
    Local cBody         := Self:GetContent()
    Local oJsonBody     := JsonObject():New()
    Local cJsonErr      := ""
    Local oResp         := JsonObject():New()
    Local aLog          := {}
    Local cErro         := ""
    Local nY            := 0
    Local nX            := 0
    Local cNumPedido    := ""
    Local cFornece      := ""
    Local cLoja         := ""
    Local cCond         := ""
    Local dEmissao      := Date()
    Local aItensJson    := {}
    Local oItemJson
    Local cProduto      := ""
    Local nQuant        := 0
    Local nPreco        := 0
    Local nTotal        := 0
    Private lMsHelpAuto     := .T.
    Private lAutoErrNoFile  := .T.
    Private lMsErroAuto     := .F.

    If Empty(cBody)
        SetRestFault(400, "Body vazio")
        Return .F.
    EndIf

    cJsonErr := oJsonBody:FromJson(cBody)

    If !Empty(cJsonErr)
        SetRestFault(400, "JSON invalido: " + cJsonErr)
        Return .F.
    EndIf

    cFornece := IIf(Empty(oJsonBody:GetJsonObject("fornecedor")), "", cValToChar(oJsonBody:GetJsonObject("fornecedor")))
    cLoja    := IIf(Empty(oJsonBody:GetJsonObject("loja")), "", cValToChar(oJsonBody:GetJsonObject("loja")))
    cCond    := IIf(Empty(oJsonBody:GetJsonObject("condicao_pagamento")), "", cValToChar(oJsonBody:GetJsonObject("condicao_pagamento")))

    If oJsonBody:HasProperty("data_emissao") .And. !Empty(oJsonBody:GetJsonObject("data_emissao"))
        dEmissao := CtoD(cValToChar(oJsonBody:GetJsonObject("data_emissao")))
    EndIf

    If Empty(cFornece)
        SetRestFault(400, "Fornecedor nao pode ficar vazio")
        Return .F.
    EndIf

    If Empty(cLoja)
        SetRestFault(400, "Loja do fornecedor nao pode ficar vazia")
        Return .F.
    EndIf

    If Empty(cCond)
        SetRestFault(400, "Condicao de pagamento nao pode ficar vazia")
        Return .F.
    EndIf

    aAdd(aCabec, {"C7_FORNECE", cFornece,  Nil})
    aAdd(aCabec, {"C7_LOJA",    cLoja,     Nil})
    aAdd(aCabec, {"C7_COND",    cCond,     Nil})
    aAdd(aCabec, {"C7_EMISSAO", dEmissao,  Nil})
    aAdd(aCabec, {"C7_FILIAL",  xFilial("SC7"), Nil})

    If ValType(oJsonBody:Get("itens")) == "A"
        aItensJson := oJsonBody:Get("itens")

        If Len(aItensJson) == 0
            SetRestFault(400, "Lista de itens nao pode ficar vazia")
            Return .F.
        EndIf

        For nX := 1 To Len(aItensJson)
            oItemJson := aItensJson[nX]

            cProduto := IIf(Empty(oItemJson:GetJsonObject("produto")), "", cValToChar(oItemJson:GetJsonObject("produto")))
            nQuant   := IIf(Empty(oItemJson:GetJsonObject("quantidade")), 0, Val(cValToChar(oItemJson:GetJsonObject("quantidade"))))
            nPreco   := IIf(Empty(oItemJson:GetJsonObject("preco")), 0, Val(cValToChar(oItemJson:GetJsonObject("preco"))))
            nTotal   := IIf(Empty(oItemJson:GetJsonObject("total")), nQuant * nPreco, Val(cValToChar(oItemJson:GetJsonObject("total"))))

            If Empty(cProduto)
                SetRestFault(400, "Produto no item " + cValToChar(nX) + " nao pode ficar vazio")
                Return .F.
            EndIf

            If nQuant <= 0
                SetRestFault(400, "Quantidade no item " + cValToChar(nX) + " deve ser maior que zero")
                Return .F.
            EndIf

            If nPreco <= 0
                SetRestFault(400, "Preco no item " + cValToChar(nX) + " deve ser maior que zero")
                Return .F.
            EndIf

            aItem := {}
            aAdd(aItem, {"C7_PRODUTO", cProduto, Nil})
            aAdd(aItem, {"C7_QUANT",   nQuant,   Nil})
            aAdd(aItem, {"C7_PRECO",   nPreco,   Nil})
            aAdd(aItem, {"C7_TOTAL",   nTotal,   Nil})
            aAdd(aItem, {"C7_ITEM",    StrZero(nX, 4), Nil})

            aAdd(aItens, aItem)
        Next nX
    Else
        SetRestFault(400, "Itens devem ser enviados como array")
        Return .F.
    EndIf

    MSExecAuto({|a,b,c| MATA120(a,b,c)}, 1, aCabec, aItens, 3)

    If lMsErroAuto
        aLog := GetAutoGRLog()
        cErro := ""
        For nY := 1 To Len(aLog)
            If !Empty(cErro)
                cErro += " | "
            EndIf
            cErro += AllTrim(aLog[nY])
        Next nY

        ConOut("Erro ao criar Pedido de Compra: " + cErro)
        SetRestFault(500, "Erro ao criar Pedido de Compra: " + cErro)
        Return .F.
    Else
        cNumPedido := SC7->C7_NUM
        ConOut("Pedido de Compra criado com sucesso! Numero: " + cNumPedido)
    EndIf

    oResp:Set("status", "sucesso")
    oResp:Set("numero_pedido", cNumPedido)
    oResp:Set("fornecedor", cFornece)
    oResp:Set("loja", cLoja)
    oResp:Set("itens_processados", Len(aItens))

    Self:SetResponse(EncodeUTF8(oResp:ToJson()))

    FreeObj(oJsonBody)
    FreeObj(oResp)
    RestArea(aArea)
Return .T.

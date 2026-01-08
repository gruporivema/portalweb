#INCLUDE "totvs.CH"
#INCLUDE "restful.CH"
#INCLUDE "FWMVCDEF.CH"
#INCLUDE "rwmake.ch"
#INCLUDE "topconn.ch"
#INCLUDE "parmtype.ch"
#INCLUDE "protheus.CH"

WSRESTFUL PRODCHECK DESCRIPTION "API PARA VALIDAR PRODUTOS E PARA ENVIAR PEDIDOS DE COMPRA"
    WSMETHOD POST seekProdutos DESCRIPTION "Valida uma lista de produtos" WSSYNTAX "/api/seekProdutos" PATH "/api/seekProdutos" PRODUCES APPLICATION_JSON
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

#Include "Protheus.ch"
#Include "TopConn.ch"
#Include "FWBrowse.ch"
#INCLUDE "fileio.ch"


/*/{Protheus.doc} IMPPEDCOM
Rotina de Importação de Pedidos de Compra via Excel
@type function
@author Seu Nome
@since 09/01/2026
/*/
User Function IMPPEDCOM()
    Local oDlg
    Local oFont := TFont():New("Arial",,-14,.T.)
    Local cArquivo := Space(200)
    Local oGet
    Local aItens := {}
    
    // Variáveis dos campos
    Local cFornece := Space(TamSX3("A2_COD")[1])
    Local cLoja := Space(TamSX3("A2_LOJA")[1])
    Local cNomFor := Space(40)
    Local cGrupo := Space(TamSX3("BM_GRUPO")[1])
    Local cDescGrp := Space(30)
    Local cCondPag := Space(TamSX3("E4_CODIGO")[1])
    Local cDescCond := Space(30)
    Local dEmissao := dDataBase
    
    Private oBrowse
    Private aLog := {} // Log de validações
    
    DEFINE MSDIALOG oDlg TITLE "Importação de Pedido de Compra" FROM 000,000 TO 550,700 PIXEL
    
    // Fornecedor
    @ 010,010 SAY "Fornecedor:" SIZE 050,010 OF oDlg PIXEL FONT oFont
    @ 008,070 MSGET cFornece SIZE 040,012 OF oDlg PIXEL PICTURE "@!" F3 "SA2" VALID (fValidFor(@cFornece, @cLoja, @cNomFor))
    @ 008,115 MSGET cLoja SIZE 020,012 OF oDlg PIXEL PICTURE "@!" VALID (fValidFor(@cFornece, @cLoja, @cNomFor))
    @ 010,140 SAY cNomFor SIZE 150,010 OF oDlg PIXEL COLOR CLR_BLUE
    
    // Grupo de Produto
    @ 025,010 SAY "Grupo Produto:" SIZE 050,010 OF oDlg PIXEL FONT oFont
    @ 023,070 MSGET cGrupo SIZE 040,012 OF oDlg PIXEL PICTURE "@!" F3 "SBM" VALID (fValidGrp(@cGrupo, @cDescGrp))
    @ 025,115 SAY cDescGrp SIZE 150,010 OF oDlg PIXEL COLOR CLR_BLUE
    
    // Condição de Pagamento
    @ 040,010 SAY "Cond. Pagto:" SIZE 050,010 OF oDlg PIXEL FONT oFont
    @ 038,070 MSGET cCondPag SIZE 040,012 OF oDlg PIXEL PICTURE "@!" F3 "SE4" VALID (fValidCond(@cCondPag, @cDescCond))
    @ 040,115 SAY cDescCond SIZE 150,010 OF oDlg PIXEL COLOR CLR_BLUE
    
    // Data de Emissão
    @ 055,010 SAY "Dt. Emissão:" SIZE 050,010 OF oDlg PIXEL FONT oFont
    @ 053,070 MSGET dEmissao SIZE 050,012 OF oDlg PIXEL
    
    // Arquivo Excel
    @ 070,010 SAY "Arquivo Excel:" SIZE 050,010 OF oDlg PIXEL FONT oFont
    @ 068,070 MSGET oGet VAR cArquivo SIZE 230,012 OF oDlg PIXEL READONLY
    @ 068,305 BUTTON "..." SIZE 020,012 OF oDlg PIXEL ACTION (cArquivo := cGetFile("Arquivos Excel (*.xls;*.xlsx)|*.xls;*.xlsx","Selecione o arquivo",1,"",.T.,GETF_LOCALHARD+GETF_NETWORKDRIVE,.F.,.F.), oGet:Refresh())
    
    @ 090,010 BUTTON "Importar Dados" SIZE 060,015 OF oDlg PIXEL ACTION (aItens := fImportaExcel(cArquivo, cGrupo, cFornece), fMontaBrowse(oDlg, @oBrowse, aItens))
    @ 090,075 BUTTON "Ver Logs" SIZE 040,015 OF oDlg PIXEL ACTION (fExibeLog())
    
    @ 090,230 BUTTON "Gerar Pedido" SIZE 060,015 OF oDlg PIXEL ACTION (fGeraPedido(aItens, cFornece, cLoja, cCondPag, dEmissao), oDlg:End())
    @ 090,295 BUTTON "Cancelar" SIZE 030,015 OF oDlg PIXEL ACTION oDlg:End()
    
    ACTIVATE MSDIALOG oDlg CENTERED
    
Return

/*/{Protheus.doc} fImportaExcel
Função para importar dados do Excel
@type function
@param cArquivo, character, Caminho do arquivo
@param cGrupo, character, Grupo de produto
@param cFornece, character, Código do fornecedor
@return array, Array com os itens importados
/*/
Static Function fImportaExcel(cArquivo, cGrupo, cFornece)
    Local aItens := {}
    Local aLog   := {}
    Local aDados := {}
    Local oArquivo

    If Empty(cArquivo)
        MsgAlert("Selecione um arquivo para importar!", "Atenção")
        Return aItens
    EndIf

    If !File(cArquivo)
        MsgAlert("Arquivo não encontrado!", "Erro")
        Return aItens
    EndIf

    If Empty(cGrupo)
        MsgAlert("Informe o Grupo de Produto antes de importar!", "Atenção")
        Return aItens
    EndIf

    If Empty(cFornece)
        MsgAlert("Informe o Fornecedor antes de importar!", "Atenção")
        Return aItens
    EndIf

    aLog := {}

    // ------------------------------------------------
    // LE CSV E MONTA aDados (MESMO PAPEL DO EXCEL)
    // ------------------------------------------------
    aDados := fCarregaCSV(cArquivo)

    

    If Len(aDados) == 0
        MsgAlert("Arquivo CSV sem dados válidos!", "Atenção")
        Return aItens
    EndIf

    // ------------------------------------------------
    // CHAMADA IDÊNTICA AO EXCEL
    // ------------------------------------------------
 FWMsgRun( ;
    NIL, ;
    {|| aItens := fProcessaPlanilha(aDados, cGrupo, cFornece, @aLog) }, ;
    "Aguarde", ;
    "Processando dados..." ;
)


    If Len(aItens) == 0
        MsgAlert("Nenhum item válido encontrado na planilha!", "Atenção")
    Else
        MsgInfo( ;
            "Total de " + cValToChar(Len(aItens)) + " itens válidos importados!" + CRLF + ;
            "Itens rejeitados: " + cValToChar(Len(aLog)), ;
            "Sucesso" ;
        )
    EndIf

Return aItens

Static Function fCarregaCSV(cArquivo)
    Local oArquivo
    Local aDados := {}
    Local cLinha := ""
    Local aLinha := {}
    Local nLinha := 0

    oArquivo := FWFileReader():New(cArquivo)

    If !oArquivo:Open()
        Return aDados
    EndIf

    While oArquivo:HasLine()
        nLinha++
        cLinha := oArquivo:GetLine()

        // ignora cabeçalho
        If nLinha == 1 .And. "Produto" $ Lower(cLinha)
            Loop
        EndIf

        aLinha := StrTokArr(cLinha, ";")

        If Len(aLinha) > 0
            aAdd(aDados, aLinha)
        EndIf
    EndDo

    oArquivo:Close()

Return aDados


/*/{Protheus.doc} fProcessaPlanilha
Processa a planilha Excel e retorna array com dados VÁLIDOS
@type function
@param cArquivo, character, Caminho do arquivo
@param cGrupo, character, Grupo de produto
@param cFornece, character, Código do fornecedor
@return array, Itens processados e validados
/*/
Static Function fProcessaPlanilha(aDados, cGrupo, cFornece)
    Local aRet := {}
    Local aLinha := {}
    Local aCSV   := {}
    Local nI
    Local cProduto := ""
    Local cProdNorm := ""
    Local cMotivo := ""
    Local nLinha := 0
    
    For nI := 1 To Len(aDados)

        nLinha++
        aLinha  := {}
        cMotivo := ""

        // Linha do CSV
        aCSV := aDados[nI]

        // Coluna A - Código Produto
        cProduto := AllTrim(aCSV[1])

        If Empty(cProduto)
            Loop
        EndIf

        // Normaliza produto
        cProdNorm := fNormalizaProduto(cProduto, cGrupo, cFornece)

        // Monta linha final (MESMA estrutura que você já tinha)
       // Monta linha final
        aAdd(aLinha, cProdNorm)                        // [1] Produto
        aAdd(aLinha, Val(aCSV[2]))                     // [2] Quantidade
        aAdd(aLinha, Val(aCSV[3]))                     // [3] Valor Unitário
        aAdd(aLinha, Val(aCSV[4]))                     // [4] Desconto
        aAdd(aLinha, Val(aCSV[5]))                     // [5] ICMS
        aAdd(aLinha, Val(aCSV[6]))                     // [6] Base ICMS
        aAdd(aLinha, 0)                                // [7] Alíquota ICMS (NÃO VEM NO CSV)
        aAdd(aLinha, Val(aCSV[7]))                     // [8] Alíquota IPI
        aAdd(aLinha, "")                               // [9] Status
        aAdd(aLinha, "")                               // [10] Motivo
        // VALIDAÇÃO 1: Produto existe
        If !fProdutoExiste(cProdNorm)
            cMotivo := "Produto não encontrado no cadastro"
            fAddLog(nLinha, cProduto, cProdNorm, cMotivo)
            Loop
        EndIf

        // VALIDAÇÃO 2: ICMS 4% exige origem = 2
        If aLinha[7] == 4
            If !fValidaOrigemICMS(cProdNorm)
                cMotivo := "ICMS 4% exige B1_ORIGEM = 2"
                fAddLog(nLinha, cProduto, cProdNorm, cMotivo)
                Loop
            EndIf
        EndIf

        // Item válido
        aLinha[9] := "VÁLIDO"
        aAdd(aRet, aLinha)

    Next nI

Return aRet


/*/{Protheus.doc} fNormalizaProduto
Normaliza código do produto conforme regras por grupo e fornecedor
@type function
@param cCodigo, character, Código original do produto
@param cGrupo, character, Grupo de produto
@param cFornece, character, Código do fornecedor
@return character, Código normalizado
/*/
Static Function fNormalizaProduto(cCodigo, cGrupo, cFornece)
    Local cRet := AllTrim(cCodigo)
    Local cNumeros := ""
    Local nI
    
    If Empty(cRet)
        Return cRet
    EndIf
    
    // GRUPO 0052 (JF)
    If cGrupo == "0052" .And. Upper(AllTrim(cFornece)) == "JF"
        cNumeros := ""
        For nI := 1 To Len(cRet)
            If IsDigit(SubStr(cRet, nI, 1))
                cNumeros += SubStr(cRet, nI, 1)
            EndIf
        Next nI
        cNumeros := PadR(cNumeros, 8, "0")
        cNumeros := Left(cNumeros, 8)
        If Len(cNumeros) >= 2
            cRet := SubStr(cNumeros, 1, 2) + "." + SubStr(cNumeros, 3, 6)
        Else
            cRet := cNumeros
        EndIf
        
    ElseIf cGrupo == "0009"
        cRet := AllTrim(cCodigo)
        
    ElseIf cGrupo == "0008" .And. Upper(AllTrim(cFornece)) == "JAN"
        cNumeros := ""
        For nI := 1 To Len(cRet)
            If IsDigit(SubStr(cRet, nI, 1))
                cNumeros += SubStr(cRet, nI, 1)
            EndIf
        Next nI
        If Len(cNumeros) >= 18
            cNumeros := SubStr(cNumeros, 11, 8)
        Else
            If Len(cNumeros) >= 8
                cNumeros := Right(cNumeros, 8)
            Else
                cNumeros := PadL(cNumeros, 8, "0")
            EndIf
        EndIf
        If Len(cNumeros) >= 8
            cRet := SubStr(cNumeros, 1, 3) + "." + SubStr(cNumeros, 4, 2) + "." + SubStr(cNumeros, 6, 3)
        Else
            cRet := cNumeros
        EndIf
        
    ElseIf cGrupo == "0007" .And. Upper(AllTrim(cFornece)) == "TATU"
        cNumeros := ""
        For nI := 1 To Len(cRet)
            If IsDigit(SubStr(cRet, nI, 1))
                cNumeros += SubStr(cRet, nI, 1)
            EndIf
        Next nI
        cRet := cNumeros
        
    ElseIf cGrupo == "0005" .And. Upper(AllTrim(cFornece)) == "MACDON"
        While Left(cRet, 1) == "0" .And. Len(cRet) > 1
            cRet := SubStr(cRet, 2)
        EndDo
        
    ElseIf cGrupo == "0004" .And. Upper(AllTrim(cFornece)) == "JUMIL"
        cNumeros := ""
        For nI := 1 To Len(cRet)
            If IsDigit(SubStr(cRet, nI, 1))
                cNumeros += SubStr(cRet, nI, 1)
            EndIf
        Next nI
        cNumeros := PadL(cNumeros, 7, "0")
        If Len(cNumeros) >= 7
            cRet := SubStr(cNumeros, 1, 2) + "." + SubStr(cNumeros, 3, 2) + "." + SubStr(cNumeros, 5, 3)
        Else
            cRet := cNumeros
        EndIf
        
    ElseIf cGrupo == "0003" .And. Upper(AllTrim(cFornece)) == "JACTO"
        cNumeros := ""
        For nI := 1 To Len(cRet)
            If IsDigit(SubStr(cRet, nI, 1))
                cNumeros += SubStr(cRet, nI, 1)
            EndIf
        Next nI
        If Len(cNumeros) == 4
            cNumeros := PadL(cNumeros, 4, "0")
            cRet := "00" + SubStr(cNumeros, 1, 1) + "." + SubStr(cNumeros, 2, 3)
        ElseIf Len(cNumeros) == 7
            cRet := SubStr(cNumeros, 1, 3) + "." + SubStr(cNumeros, 4, 4)
        Else
            If Len(cNumeros) <= 4
                cNumeros := PadL(cNumeros, 4, "0")
                cRet := "00" + SubStr(cNumeros, 1, 1) + "." + SubStr(cNumeros, 2, 3)
            Else
                cRet := SubStr(cNumeros, 1, 3) + "." + SubStr(cNumeros, 4)
            EndIf
        EndIf
        
    ElseIf cGrupo == "0002" .And. Upper(AllTrim(cFornece)) == "KUHN"
        cRet := AllTrim(cCodigo)
        
    ElseIf cGrupo == "0001" .And. Upper(AllTrim(cFornece)) == "HORSH"
        cRet := AllTrim(cCodigo)
        
    ElseIf cGrupo == "OUTROS" .Or. Upper(AllTrim(cFornece)) == "OUTROS"
        cRet := AllTrim(cCodigo)
    EndIf
    
Return cRet

/*/{Protheus.doc} fProdutoExiste
Valida se o produto existe no cadastro (SB1)
@type function
@param cProduto, character, Código do produto
@return logical, .T. se existe, .F. se não existe
/*/
Static Function fProdutoExiste(cProduto)
    Local lRet := .F.
    Local aArea := GetArea()
    
    DbSelectArea("SB1")
    SB1->(DbSetOrder(1)) // B1_FILIAL + B1_COD
    
    If SB1->(DbSeek(xFilial("SB1") + cProduto))
        lRet := .T.
    EndIf
    
    RestArea(aArea)
Return lRet

/*/{Protheus.doc} fValidaOrigemICMS
Valida se produto com ICMS 4% tem B1_ORIGEM = 2
@type function
@param cProduto, character, Código do produto
@return logical, .T. se válido, .F. se inválido
/*/
Static Function fValidaOrigemICMS(cProduto)
    Local lRet := .F.
    Local aArea := GetArea()
    
    DbSelectArea("SB1")
    SB1->(DbSetOrder(1))
    
    If SB1->(DbSeek(xFilial("SB1") + cProduto))
        If SB1->B1_ORIGEM == "2"
            lRet := .T.
        EndIf
    EndIf
    
    RestArea(aArea)
Return lRet

/*/{Protheus.doc} fAddLog
Adiciona registro no log de validações
@type function
@param nLinha, numeric, Número da linha na planilha
@param cProdOrig, character, Código original
@param cProdNorm, character, Código normalizado
@param cMotivo, character, Motivo da rejeição
/*/
Static Function fAddLog(nLinha, cProdOrig, cProdNorm, cMotivo)
    Local aItem := {}
    
    aAdd(aItem, nLinha)       // [1] Linha
    aAdd(aItem, cProdOrig)    // [2] Código Original
    aAdd(aItem, cProdNorm)    // [3] Código Normalizado
    aAdd(aItem, cMotivo)      // [4] Motivo
    
    aAdd(aLog, aItem)
Return

/*/{Protheus.doc} fExibeLog
Exibe tela com log de validações
@type function
/*/
Static Function fExibeLog()
    Local oDlgLog
    Local oBrwLog
    Local aHeader := {"Linha", "Cód. Original", "Cód. Normalizado", "Motivo Rejeição"}
    
    If Len(aLog) == 0
        MsgInfo("Nenhum erro de validação registrado!", "Log")
        Return
    EndIf
    
    DEFINE MSDIALOG oDlgLog TITLE "Log de Validações - Itens Rejeitados" FROM 000,000 TO 400,800 PIXEL
    
    oBrwLog := TCBrowse():New(010,010,390,180,,aHeader,,oDlgLog,,,,,,,,,,,,.F.,,.T.,,.F.,,,)
    oBrwLog:SetArray(aLog)
    
    oBrwLog:bLine := {|| {;
        Transform(aLog[oBrwLog:nAt,1], "@E 999,999"),;
        aLog[oBrwLog:nAt,2],;
        aLog[oBrwLog:nAt,3],;
        aLog[oBrwLog:nAt,4]}}
    
    @ 175,350 BUTTON "Fechar" SIZE 040,012 OF oDlgLog PIXEL ACTION oDlgLog:End()
    
    ACTIVATE MSDIALOG oDlgLog CENTERED
    
Return

/*/{Protheus.doc} fMontaBrowse
Monta browse com os dados importados
@type function
/*/
Static Function fMontaBrowse(oDlg, oBrowse, aItens)
    Local aHeader := {"Produto", "Quantidade", "Vlr Unit", "Desconto", "ICMS", "Base ICMS", "Aliq ICMS", "Aliq IPI", "Status"}
    
    If oBrowse != Nil
        oBrowse:DeActivate()
        oBrowse:Hide()
    EndIf
    
    If Len(aItens) == 0
        Return
    EndIf
    
    oBrowse := TCBrowse():New(110,010,330,150,,aHeader,,oDlg,,,,,,,,,,,,.F.,,.T.,,.F.,,,)
    oBrowse:SetArray(aItens)
    
    oBrowse:bLine := {|| {;
        aItens[oBrowse:nAt,1],;
        Transform(aItens[oBrowse:nAt,2], "@E 999,999.99"),;
        Transform(aItens[oBrowse:nAt,3], "@E 999,999.99"),;
        Transform(aItens[oBrowse:nAt,4], "@E 999,999.99"),;
        Transform(aItens[oBrowse:nAt,5], "@E 999,999.99"),;
        Transform(aItens[oBrowse:nAt,6], "@E 999,999.99"),;
        Transform(aItens[oBrowse:nAt,7], "@E 99.99"),;
        Transform(aItens[oBrowse:nAt,8], "@E 99.99"),;
        aItens[oBrowse:nAt,9]}}
    
    oBrowse:Refresh()
    
Return

/*/{Protheus.doc} fGeraPedido
Gera o pedido de compra via ExecAuto (MATA120)
@type function
@param aItens, array, Itens validados
@param cFornece, character, Código do Fornecedor
@param cLoja, character, Loja do Fornecedor
@param cCondPag, character, Condição de Pagamento
@param dEmissao, date, Data de Emissão
/*/
Static Function fGeraPedido(aDados, cFornece, cLoja, cCondPag, dEmissao)
    Local aCab := {}
    Local aItens := {}
    Local aLinha := {}
    Local nI
    Local lMsErroAuto := .F.
    Local cDoc
    Local aArea := GetArea()

    
    Private lMsHelpAuto := .T.
    Private lAutoErrNoFile := .T.
    
    If Len(aDados) == 0
        MsgAlert("Não há itens válidos para gerar o pedido!", "Atenção")
        Return
    EndIf
    
    // Validações obrigatórias
    If Empty(cFornece) .Or. Empty(cLoja)
        MsgAlert("Informe o Fornecedor!", "Atenção")
        Return
    EndIf
    
    If Empty(cCondPag)
        MsgAlert("Informe a Condição de Pagamento!", "Atenção")
        Return
    EndIf
    
    If !MsgYesNo("Confirma a geração do Pedido de Compra com " + cValToChar(Len(aItens)) + " itens válidos?", "Confirmação")
        Return
    EndIf
    
        dbSelectArea("SC7")
        SC7->(dbSetOrder(1))

        cDoc := GetSXENum("SC7","C7_NUM")
        While SC7->(dbSeek(xFilial("SC7")+cDoc))
            ConfirmSX8()
            cDoc := GetSXENum("SC7","C7_NUM")
        EndDo

// Monta cabeçalho do pedido
aCabec := {}
aadd(aCabec,{"C7_NUM",cDoc})
aadd(aCabec,{"C7_EMISSAO",dDataBase})
aadd(aCabec,{"C7_FORNECE",cFornece})
aadd(aCabec,{"C7_LOJA",cLoja})
aadd(aCabec,{"C7_COND",cCondPag})
aadd(aCabec,{"C7_CONTATO","AUTO"})
aadd(aCabec,{"C7_MOEDA","1",Nil})
aadd(aCabec,{"C7_TXMOEDA",1.0000,Nil})
aadd(aCabec,{"C7_FILENT",xFilial("SC7")})

aItens := {}

For nI := 1 To Len(aDados)

    aLinha := {}

    aadd(aLinha, {"C7_ITEM",    StrZero(nI, TamSX3("C7_ITEM")[1]), Nil})
    aadd(aLinha, {"C7_PRODUTO", aDados[nI,1],                      Nil})
    aadd(aLinha, {"C7_QUANT",   aDados[nI,2],                      Nil})
    aadd(aLinha, {"C7_PRECO",   aDados[nI,3],                      Nil})
    aadd(aLinha, {"C7_TOTAL",   aDados[nI,2] * aDados[nI,3],       Nil})
    aadd(aLinha, {"C7_VLDESC",  aDados[nI,4],                      Nil})
    aadd(aLinha, {"C7_VALIPI",  aDados[nI,5],                      Nil})
    aadd(aLinha, {"C7_BASEICM", aDados[nI,6],                      Nil})
    aadd(aLinha, {"C7_ALIQIPI", aDados[nI,7],                      Nil})
    aadd(aLinha, {"C7_DATPRF",  dDataBase + 7,                     Nil})

    aadd(aItens, aLinha)

Next

// Segurança extra (opcional, mas recomendado)
If Len(aItens) == 0
    MsgStop("Nenhum item montado para o pedido.")
    Return
EndIf

MSExecAuto({|a,b,c,d,e,f,g| MATA120(a,b,c,d)}, 1, aCabec, aItens, 3)

    
    If lMsErroAuto
        MostraErro()
        RollbackSX8()
        MsgAlert("Erro ao gerar Pedido de Compra! Verifique o log.", "Erro")
    Else
        confirmsx8()
        MsgInfo("Pedido de Compra " + cDoc + " gerado com sucesso!" + CRLF + ;
                "Total de itens: " + cValToChar(Len(aItens)), "Sucesso")
    EndIf

    RestArea(aArea)

    
Return

/*/{Protheus.doc} fValidFor
Valida Fornecedor
@type function
/*/
Static Function fValidFor(cFornece, cLoja, cNomFor)
    Local lRet := .T.
    
    DbSelectArea("SA2")
    SA2->(DbSetOrder(1))
    
    If SA2->(DbSeek(xFilial("SA2") + cFornece + cLoja))
        cNomFor := SA2->A2_NOME
    Else
        If !Empty(cFornece)
            MsgAlert("Fornecedor não encontrado!", "Atenção")
            lRet := .F.
        EndIf
        cNomFor := Space(40)
    EndIf
    
Return lRet

/*/{Protheus.doc} fValidGrp
Valida Grupo de Produto
@type function
/*/
Static Function fValidGrp(cGrupo, cDescGrp)
    Local lRet := .T.
    
    DbSelectArea("SBM")
    SBM->(DbSetOrder(1))
    
    If SBM->(DbSeek(xFilial("SBM") + cGrupo))
        cDescGrp := SBM->BM_DESC
    Else
        If !Empty(cGrupo)
            MsgAlert("Grupo de Produto não encontrado!", "Atenção")
            lRet := .F.
        EndIf
        cDescGrp := Space(30)
    EndIf
    
Return lRet

/*/{Protheus.doc} fValidCond
Valida Condição de Pagamento
@type function
/*/
Static Function fValidCond(cCondPag, cDescCond)
    Local lRet := .T.
    
    DbSelectArea("SE4")
    SE4->(DbSetOrder(1))
    
    If SE4->(DbSeek(xFilial("SE4") + cCondPag))
        cDescCond := SE4->E4_DESCRI
    Else
        If !Empty(cCondPag)
            MsgAlert("Condição de Pagamento não encontrada!", "Atenção")
            lRet := .F.
        EndIf
        cDescCond := Space(30)
    EndIf
    
Return lRet

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
    @ 070,010 SAY "Arquivo CSV ou XML:" SIZE 050,010 OF oDlg PIXEL FONT oFont
    @ 068,070 MSGET oGet VAR cArquivo SIZE 230,012 OF oDlg PIXEL READONLY
    @ 068,305 BUTTON "..." SIZE 020,012 OF oDlg PIXEL ACTION (cArquivo := cGetFile("Arquivos Excel (*.csv;*.xml)|*.csv;*.xml","Selecione o arquivo",1,"",.T.,GETF_LOCALHARD+GETF_NETWORKDRIVE,.F.,.F.), oGet:Refresh())
    
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
    Local aDados := {}

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

    // ------------------------------------
    // CSV ou XML
    // ------------------------------------
    If Lower(Right(cArquivo, 4)) == ".xml"
        aDados := fCarregaXMLNFe(cArquivo)
    Else
        aDados := fCarregaCSV(cArquivo)
    EndIf

    If ValType(aDados) <> "A" .Or. Len(aDados) == 0
        MsgAlert("Arquivo sem dados válidos!", "Atenção")
        Return aItens
    EndIf

    // ------------------------------------
    // Processamento único
    // ------------------------------------
    FWMsgRun( ;
        NIL, ;
        {|| aItens := fProcessaPlanilha(aDados, cGrupo, cFornece, @aLog) }, ;
        "Aguarde", ;
        "Processando dados..." ;
    )

    If Len(aItens) == 0
        If Len(aLog)>0 
            MsgInfo( ;
                        "Total de " + cValToChar(Len(aItens)) + " itens válidos importados!" + CRLF + ;
                        "Itens rejeitados: " + cValToChar(Len(aLog)), ;
                        "Sucesso" ;
                    )
        endif 
        MsgAlert("Nenhum item válido encontrado!", "Atenção")
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


ConOut("DEBUG PLANILHA - Linha " + cValToChar(nI))
ConOut("Tipo aCSV: " + ValType(aCSV))
ConOut("Len aCSV : " + cValToChar(If(ValType(aCSV)=="A", Len(aCSV), 0)))

If ValType(aCSV) == "A"
    ConOut("Conteúdo aCSV: " + cValToChar(aCSV))
EndIf
    
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
       // Monta linha final (PADRÃO ÚNICO)
        aAdd(aLinha, cProdNorm)                         // [1] Produto
        aAdd(aLinha, fValDecimal(aCSV[2], 6))           // [2] Quantidade
        aAdd(aLinha, fValDecimal(aCSV[3], 6))           // [3] Valor Unitário
        aAdd(aLinha, fValDecimal(aCSV[4], 6))           // [4] Desconto
        aAdd(aLinha, fValDecimal(aCSV[5], 6))           // [5] Valor ICMS
        aAdd(aLinha, fValDecimal(aCSV[6], 6))           // [6] Base ICMS
        aAdd(aLinha, fValDecimal(aCSV[7], 6))           // [7] Alíquota Icms
        aAdd(aLinha, fValDecimal(aCSV[8], 6))           // [8] Alíquota IPI
        aAdd(aLinha, "")                                // [9] Status
        aAdd(aLinha, "")                                // [10] Motivo


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
Static Function fValDecimal(cValor, nDec)
    Local nRet := 0

    If ValType(cValor) <> "C"
        Return 0
    EndIf

    cValor := AllTrim(cValor)

    If Empty(cValor)
        Return 0
    EndIf

    // Remove espaços
    cValor := StrTran(cValor, " ", "")

    /*
        REGRA:
        - Se tiver vírgula, assume CSV/planilha brasileira
        - Se tiver ponto, assume XML
        - Nunca existe milhar nos seus arquivos
    */

    If "," $ cValor
        // CSV: troca vírgula por ponto
        cValor := StrTran(cValor, ".", "") // segurança (milhar)
        cValor := StrTran(cValor, ",", ".")
    EndIf

    nRet := Val(cValor)

    If nDec > 0
        nRet := Round(nRet, nDec)
    EndIf

Return nRet

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
    If cGrupo == "0052" 
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
        
    ElseIf cGrupo == "0008" 
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
        
    ElseIf cGrupo == "0007" 
        cNumeros := ""
        For nI := 1 To Len(cRet)
            If IsDigit(SubStr(cRet, nI, 1))
                cNumeros += SubStr(cRet, nI, 1)
            EndIf
        Next nI
        cRet := cNumeros
        
    ElseIf cGrupo == "0005" 
        While Left(cRet, 1) == "0" .And. Len(cRet) > 1
            cRet := SubStr(cRet, 2)
        EndDo
        
    ElseIf cGrupo == "0004" 
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
        
        ElseIf cGrupo == "0003"

            cNumeros := ""

            // 1) Mantém apenas dígitos
            For nI := 1 To Len(cRet)
                If IsDigit(SubStr(cRet, nI, 1))
                    cNumeros += SubStr(cRet, nI, 1)
                EndIf
            Next nI

            // 2) Remove zeros à esquerda
            Do While Len(cNumeros) > 1 .And. SubStr(cNumeros, 1, 1) == "0"
                cNumeros := SubStr(cNumeros, 2)
            EndDo

            // 3) Segurança: se virar vazio
            If Empty(cNumeros)
                cNumeros := "0"
            EndIf

            // 4) Aplica regras de formatação
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

        
    ElseIf cGrupo == "0002"
        cRet := AllTrim(cCodigo)
        
    ElseIf cGrupo == "0001"
        cRet := AllTrim(cCodigo)
        
    ElseIf !cGrupo $ ("0001/0002/0003/0004/0005/0006/0007/0008/0009/0052")
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

        If ALLTRIM(SB1->B1_COD) == ALLTRIM(cProduto) .AND. SB1->B1_MSBLQL =='2'
            lRet := .T.
        EndIf 

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
/*/Static Function fExibeLog()
    Local oDlgLog
    Local oBrwLog
    Local aHeader := {"Linha", "Cód. Original", "Cód. Normalizado", "Motivo Rejeição"}

    If Len(aLog) == 0
        MsgInfo("Nenhum erro de validação registrado!", "Log")
        Return
    EndIf

    DEFINE MSDIALOG oDlgLog ;
        TITLE "Log de Validações - Itens Rejeitados" ;
        FROM 000,000 TO 400,800 PIXEL

    oBrwLog := TCBrowse():New( ;
        010,010,390,180,, ;
        aHeader,, ;
        oDlgLog,,,,,,,,,,,, ;
        .F.,,.T.,,.F.,,, )

    oBrwLog:SetArray(aLog)

    oBrwLog:bLine := {|| { ;
        Transform(aLog[oBrwLog:nAt,1], "@E 999,999"), ;
        aLog[oBrwLog:nAt,2], ;
        aLog[oBrwLog:nAt,3], ;
        aLog[oBrwLog:nAt,4] } }

    @ 175,350 BUTTON "Fechar" SIZE 040,012 OF oDlgLog PIXEL ;
        ACTION oDlgLog:End()

    ACTIVATE MSDIALOG oDlgLog CENTERED

Return


/*/{Protheus.doc} fMontaBrowse
Monta browse com os dados importados
@type function
/*/
Static Function fMontaBrowse(oDlg, oBrowse, aItens)
    Local aHeader := { ;
        "Produto", ;
        "Quantidade", ;
        "Vlr Unit", ;
        "Desconto", ;
        "ICMS", ;
        "Base ICMS", ;
        "Aliq ICMS", ;
        "Aliq IPI", ;
        "Status" ;
    }

    // ------------------------------------
    // Remove browse anterior (se existir)
    // ------------------------------------
    If oBrowse != Nil
        oBrowse:Hide()
        oBrowse := Nil
    EndIf

    If ValType(aItens) <> "A" .Or. Len(aItens) == 0
        Return
    EndIf

    // ------------------------------------
    // Cria novo browse
    // ------------------------------------
    oBrowse := TCBrowse():New( ;
        110,010,330,150,, ;
        aHeader,, ;
        oDlg,,,,,,,,,,,, ;
        .F.,,.T.,,.F.,,, )

    oBrowse:SetArray(aItens)

    // ------------------------------------
    // Define layout das linhas
    // ------------------------------------
    oBrowse:bLine := {|| { ;
        aItens[oBrowse:nAt,1], ;
        Transform(aItens[oBrowse:nAt,2], "@E 999,999.99"), ;
        Transform(aItens[oBrowse:nAt,3], "@E 999,999.99"), ;
        Transform(aItens[oBrowse:nAt,4], "@E 999,999.99"), ;
        Transform(aItens[oBrowse:nAt,5], "@E 999,999.99"), ;
        Transform(aItens[oBrowse:nAt,6], "@E 999,999.99"), ;
        Transform(aItens[oBrowse:nAt,7], "@E 99.99"), ;
        Transform(aItens[oBrowse:nAt,8], "@E 99.99"), ;
        aItens[oBrowse:nAt,9] ;
    } }

    oBrowse:Refresh()

Return
Static Function fGeraPedido(aItens, cFornece, cLoja, cCondPag, dEmissao)
    Local aCabec := {}
    Local aItensPC := {}
    Local aLinha := {}
    Local nI
    Local cNumPC := ""
    Local aArea := GetArea()
    Local nOpcao := 3 // 3=Incluir, 4=Alterar, 5=Excluir
    Local cLog := ""
    
    Private lMsErroAuto := .F.
    Private lMsHelpAuto := .T.
    Private lAutoErrNoFile := .T.
    
    
    If Len(aItens) == 0
        ConOut("ERRO: Nenhum item válido para gerar pedido")
        MsgAlert("Não há itens válidos para gerar o pedido!", "Atenção")
        Return
    EndIf
    
    // LOG 2: Validação de fornecedor
    ConOut("LOG 2: Validando fornecedor")
    ConOut("Fornecedor: [" + cFornece + "]")
    ConOut("Loja: [" + cLoja + "]")
    
    If Empty(cFornece) .Or. Empty(cLoja)
        ConOut("ERRO: Fornecedor ou loja vazios")
        MsgAlert("Informe o Fornecedor!", "Atenção")
        Return
    EndIf
    
    // LOG 3: Validação de condição de pagamento
    ConOut("LOG 3: Validando condição de pagamento")
    ConOut("Condição Pagamento: [" + cCondPag + "]")
    
    If Empty(cCondPag)
        ConOut("ERRO: Condição de pagamento vazia")
        MsgAlert("Informe a Condição de Pagamento!", "Atenção")
        Return
    EndIf
    
    // LOG 4: Validação de data
    ConOut("LOG 4: Validando data de emissão")
    ConOut("Data Emissão: " + DtoC(dEmissao))
    
    If Empty(dEmissao)
        ConOut("ERRO: Data de emissão vazia")
        MsgAlert("Informe a Data de Emissão!", "Atenção")
        Return
    EndIf
    
    If !MsgYesNo("Confirma a geração do Pedido de Compra com " + cValToChar(Len(aItens)) + " itens válidos?", "Confirmação")
        ConOut("CANCELADO: Usuário cancelou a operação")
        Return
    EndIf
    
    
    aCabec := {}
    
    aAdd(aCabec, {"C7_EMISSAO", dEmissao,         Nil})
    
    aAdd(aCabec, {"C7_FORNECE", cFornece,         Nil})
    
    aAdd(aCabec, {"C7_LOJA",    cLoja,            Nil})
    
    aAdd(aCabec, {"C7_COND",    cCondPag,         Nil})
    
    aAdd(aCabec, {"C7_CONTATO", "AUTO",           Nil})
    
    aAdd(aCabec, {"C7_FILENT",  xFilial("SC7"),   Nil})
    
        
    aItensPC := {}
    For nI := 1 To Len(aItens)
        
        aLinha := {}
        
        // Campos obrigatórios
        aAdd(aLinha, {"C7_ITEM",    StrZero(nI, TamSX3("C7_ITEM")[1]), Nil})
        
        aAdd(aLinha, {"C7_PRODUTO", aItens[nI,1],                      Nil})
        
        aAdd(aLinha, {"C7_QUANT",   aItens[nI,2],                      Nil})
        
        aAdd(aLinha, {"C7_PRECO",   aItens[nI,3],                      Nil})
        
        aAdd(aLinha, {"C7_TOTAL",   aItens[nI,2] * aItens[nI,3],       Nil})
        
        aAdd(aLinha, {"C7_DATPRF",  dEmissao + 7,                      Nil})

        aAdd(aLinha, {"C7_VLDESC", aItens[nI,4], Nil})

        aAdd(aLinha, {"C7_VALICM ", aItens[nI,5], Nil})  

        aAdd(aLinha, {"C7_BASEICM", aItens[nI,6], Nil})

        aAdd(aLinha, {"C7_ALIQIPI", aItens[nI,7], Nil})
        
        
        aAdd(aItensPC, aLinha)
    Next nI
    
    
    
    If Len(aItensPC) == 0
        ConOut("ERRO: Nenhum item montado")
        MsgStop("Nenhum item montado para o pedido.", "Atenção")
        RollBackSX8()
        RestArea(aArea)
        Return
    EndIf
    

    ConOut("Iniciando ExecAuto...")
    
    MSExecAuto({|v,x,y,z| MATA120(v,x,y,z)}, 1, aCabec, aItensPC, nOpcao)
    
    ConOut("ExecAuto finalizado")
    ConOut("lMsErroAuto: " + If(lMsErroAuto, "TRUE (ERRO)", "FALSE (SUCESSO)"))

    aErroAuto := GetAutoGRLog()
    For nX := 1 To Len(aErroAuto)
        ConOut("ERRO[" + StrZero(nX,3) + "]: " + aErroAuto[nX])
    Next
    
    // LOG 10: Tratamento do retorno
    If lMsErroAuto
        ConOut("LOG 10: ERRO no ExecAuto")
        
        // Desfaz numeração
        RollBackSX8()
        ConOut("RollBackSX8() executado")
        
        // Exibe log de erro
        MostraErro()
        
        // Captura erro em arquivo
        cLog := MemoRead("\system\error.log")
        If !Empty(cLog)
            ConOut("=== CONTEÚDO DO ERROR.LOG ===")
            ConOut(cLog)
            ConOut("=== FIM ERROR.LOG ===")
        EndIf
        
        MsgAlert("Erro ao gerar Pedido de Compra!" + CRLF + ;
                 "Verifique o console do AppServer para detalhes.", "Erro ExecAuto")
        
        ConOut("ERRO DETALHADO:")
        ConOut("Verifique a tela de erro (MostraErro) que foi exibida")
        
    Else
        ConOut("LOG 10: SUCESSO no ExecAuto")
        
        // Confirma numeração
        ConfirmSX8()
        ConOut("ConfirmSX8() executado")
        
        // Verifica se pedido foi gravado
        DbSelectArea("SC7")
        SC7->(DbSetOrder(1))
        
        If SC7->(DbSeek(xFilial("SC7") + SC7->C7_NUM))
            ConOut("CONFIRMADO: Pedido " + SC7->C7_NUM + " encontrado na base")
            ConOut("Primeiro produto: " + SC7->C7_PRODUTO)
            ConOut("Quantidade: " + cValToChar(SC7->C7_QUANT))
        Else
            ConOut("ATENÇÃO: Pedido " + SC7->C7_NUM + " NÃO encontrado na base após ExecAuto")
        EndIf
        
        MsgInfo("Pedido de Compra " + SC7->C7_NUM + " gerado com sucesso!" + CRLF + ;
                "Fornecedor: " + cFornece + "/" + cLoja + CRLF + ;
                "Total de itens: " + cValToChar(Len(aItensPC)), "Sucesso")
        
        ConOut("Pedido " + cNumPC + " gerado com SUCESSO")
    EndIf
    
    RestArea(aArea)
    ConOut("RestArea() executado")
    
    ConOut(Replicate("=", 80))
    ConOut("FIM - fGeraPedido")
    ConOut(Replicate("=", 80))
    
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
Static Function fCarregaXMLNFe(cArquivo)
    Local cXml      := ""
    Local oXml
    Local oInfNFe
    Local oDet
    Local aDados    := {}
    Local aLinha
    Local nI
    Local cError    := ""
    Local cWarning  := ""

    // ---------------------------------
    // Validação básica
    // ---------------------------------
    If ValType(cArquivo) <> "C" .Or. Empty(AllTrim(cArquivo))
        ConOut("ERRO XML: caminho inválido -> " + cValToChar(cArquivo))
        Return aDados
    EndIf

    If !File(cArquivo)
        ConOut("ERRO XML: arquivo não encontrado -> " + cArquivo)
        Return aDados
    EndIf

    // ---------------------------------
    // Lê e faz parse do XML
    // ---------------------------------
    cXml := fReadLargeFile(cArquivo)

    ConOut("XML lido. Tamanho: " + cValToChar(Len(cXml)) + " bytes")

    If Empty(cXml)
        ConOut("ERRO XML: arquivo vazio ou não foi possível ler")
        Return aDados
    EndIf

    // Remove BOM UTF-8 se existir
    If SubStr(cXml, 1, 3) == Chr(239) + Chr(187) + Chr(191)
        cXml := SubStr(cXml, 4)
    EndIf

    ConOut("XML lido. Tamanho: " + cValToChar(Len(cXml)) + " bytes")

    oXml := XmlParser(cXml, "_", @cError, @cWarning)

    If oXml == Nil
        ConOut("ERRO XML: XmlParser falhou -> " + cError)
        Return aDados
    EndIf

    // ---------------------------------
    // Acessa _INFNFE seguindo o padrão do exemplo
    // ---------------------------------
    If ValType(XmlChildEx(oXml, "_NFEPROC")) == "O"
        If ValType(XmlChildEx(oXml:_NFEPROC, "_NFE")) == "O"
            If ValType(XmlChildEx(oXml:_NFEPROC:_NFE, "_INFNFE")) == "O"
                oInfNFe := oXml:_NFEPROC:_NFE:_INFNFE
                ConOut("Tag _INFNFE localizada")
            Else
                ConOut("ERRO XML: tag _INFNFE não encontrada")
                Return aDados
            EndIf
        Else
            ConOut("ERRO XML: tag _NFE não encontrada")
            Return aDados
        EndIf
    Else
        ConOut("ERRO XML: tag _NFEPROC não encontrada")
        Return aDados
    EndIf

    // ---------------------------------
    // Acessa _DET dentro de _INFNFE
    // ---------------------------------
    If ValType(XmlChildEx(oInfNFe, "_DET")) == "U"
        ConOut("ERRO XML: tag _DET não encontrada")
        Return aDados
    EndIf

    oDet := oInfNFe:_DET

    // ---------------------------------
    // Processa os itens
    // ---------------------------------
    If ValType(oDet) == "A"
        ConOut("Total de itens: " + cValToChar(Len(oDet)))
        
        For nI := 1 To Len(oDet)
            aLinha := fExtraiItemXML(oDet[nI])
            
            If ValType(aLinha) == "A" .And. Len(aLinha) > 0
                aAdd(aDados, aLinha)
            EndIf
        Next
        
    ElseIf ValType(oDet) == "O"
        ConOut("Item único encontrado")
        
        aLinha := fExtraiItemXML(oDet)
        
        If ValType(aLinha) == "A" .And. Len(aLinha) > 0
            aAdd(aDados, aLinha)
        EndIf
    EndIf

    ConOut("Total processado: " + cValToChar(Len(aDados)) + " itens")

Return aDados

Static Function fExtraiItemXML(oDet)
    Local aLinha := {}
    Local oProd
    Local oImp
    Local cProd     := ""
    Local cQtd      := ""
    Local cVlrUnit  := ""
    Local cDesc     := ""
    Local cVlrICMS  := ""
    Local cBaseICMS := ""
    Local cAliqICMS := ""
    Local cAliqIPI  := ""

    ConOut("--- Iniciando extração de item ---")

    If oDet == Nil
        ConOut("ERRO: oDet é Nil")
        Return Nil
    EndIf

    // ---------------------------------
    // Acessa tag _PROD
    // ---------------------------------
    If ValType(XmlChildEx(oDet, "_PROD")) <> "O"
        ConOut("ERRO: Tag _PROD não encontrada")
        Return Nil
    EndIf

    oProd := oDet:_PROD
    ConOut("Tag _PROD localizada")

    // ---------------------------------
    // Extrai código do produto
    // ---------------------------------
    If ValType(XmlChildEx(oProd, "_CPROD")) <> "O"
        ConOut("ERRO: Tag _CPROD não encontrada")
        Return Nil
    EndIf

    // Acessa o conteúdo da tag diretamente
    cProd := AllTrim(oProd:_CPROD:TEXT)
    ConOut("Código produto: " + cProd)

    If Empty(cProd)
        ConOut("ERRO: Código do produto vazio")
        Return Nil
    EndIf

    // ---------------------------------
    // Extrai dados do produto
    // ---------------------------------
    If ValType(XmlChildEx(oProd, "_QCOM")) == "O"
        cQtd := AllTrim(oProd:_QCOM:TEXT)
        ConOut("Quantidade: " + cQtd)
    Else
        ConOut("Tag _QCOM não encontrada")
    EndIf

    If ValType(XmlChildEx(oProd, "_VUNCOM")) == "O"
        cVlrUnit := AllTrim(oProd:_VUNCOM:TEXT)
        ConOut("Valor Unitário: " + cVlrUnit)
    Else
        ConOut("Tag _VUNCOM não encontrada")
    EndIf

    // vDesc pode não existir no XML
    If ValType(XmlChildEx(oProd, "_VDESC")) == "O"
        cDesc := AllTrim(oProd:_VDESC:TEXT)
        ConOut("Desconto: " + cDesc)
    Else
        ConOut("Tag _VDESC não encontrada (opcional)")
        cDesc := "0"
    EndIf

    // ---------------------------------
    // Extrai impostos
    // ---------------------------------
    If ValType(XmlChildEx(oDet, "_IMPOSTO")) == "O"
        oImp := oDet:_IMPOSTO
        ConOut("Tag _IMPOSTO localizada")

        // Extrai impostos
// ---------------------------------
If ValType(XmlChildEx(oDet, "_IMPOSTO")) == "O"
    oImp := oDet:_IMPOSTO
    ConOut("Tag _IMPOSTO localizada")

            // ICMS
            If ValType(XmlChildEx(oImp, "_ICMS")) == "O"
                ConOut("Tag _ICMS localizada")

                oICMS := oImp:_ICMS
                oICMSDet := Nil

                // Descobre dinamicamente qual ICMS existe
                If ValType(XmlChildEx(oICMS, "_ICMS00")) == "O"
                    oICMSDet := oICMS:_ICMS00
                ElseIf ValType(XmlChildEx(oICMS, "_ICMS10")) == "O"
                    oICMSDet := oICMS:_ICMS10
                ElseIf ValType(XmlChildEx(oICMS, "_ICMS20")) == "O"
                    oICMSDet := oICMS:_ICMS20
                ElseIf ValType(XmlChildEx(oICMS, "_ICMS30")) == "O"
                    oICMSDet := oICMS:_ICMS30
                ElseIf ValType(XmlChildEx(oICMS, "_ICMS40")) == "O"
                    oICMSDet := oICMS:_ICMS40
                ElseIf ValType(XmlChildEx(oICMS, "_ICMS41")) == "O"
                    oICMSDet := oICMS:_ICMS41
                ElseIf ValType(XmlChildEx(oICMS, "_ICMS51")) == "O"
                    oICMSDet := oICMS:_ICMS51
                ElseIf ValType(XmlChildEx(oICMS, "_ICMS60")) == "O"
                    oICMSDet := oICMS:_ICMS60
                ElseIf ValType(XmlChildEx(oICMS, "_ICMS70")) == "O"
                    oICMSDet := oICMS:_ICMS70
                ElseIf ValType(XmlChildEx(oICMS, "_ICMS90")) == "O"
                    oICMSDet := oICMS:_ICMS90

                // Simples Nacional
                ElseIf ValType(XmlChildEx(oICMS, "_ICMSSN101")) == "O"
                    oICMSDet := oICMS:_ICMSSN101
                ElseIf ValType(XmlChildEx(oICMS, "_ICMSSN102")) == "O"
                    oICMSDet := oICMS:_ICMSSN102
                ElseIf ValType(XmlChildEx(oICMS, "_ICMSSN201")) == "O"
                    oICMSDet := oICMS:_ICMSSN201
                ElseIf ValType(XmlChildEx(oICMS, "_ICMSSN202")) == "O"
                    oICMSDet := oICMS:_ICMSSN202
                ElseIf ValType(XmlChildEx(oICMS, "_ICMSSN500")) == "O"
                    oICMSDet := oICMS:_ICMSSN500
                ElseIf ValType(XmlChildEx(oICMS, "_ICMSSN900")) == "O"
                    oICMSDet := oICMS:_ICMSSN900
                EndIf

                // Leitura segura dos campos (existindo, lê)
                If ValType(oICMSDet) == "O"

                    If ValType(XmlChildEx(oICMSDet, "_CST")) == "O"
                        cCST := AllTrim(oICMSDet:_CST:TEXT)
                        ConOut("CST: " + cCST)
                    EndIf

                    If ValType(XmlChildEx(oICMSDet, "_CSOSN")) == "O"
                        cCSOSN := AllTrim(oICMSDet:_CSOSN:TEXT)
                        ConOut("CSOSN: " + cCSOSN)
                    EndIf

                    If ValType(XmlChildEx(oICMSDet, "_VBC")) == "O"
                        cBaseICMS := AllTrim(oICMSDet:_VBC:TEXT)
                        ConOut("Base ICMS: " + cBaseICMS)
                    EndIf

                    If ValType(XmlChildEx(oICMSDet, "_PICMS")) == "O"
                        cAliqICMS := AllTrim(oICMSDet:_PICMS:TEXT)
                        ConOut("Alíquota ICMS: " + cAliqICMS)
                    EndIf

                    If ValType(XmlChildEx(oICMSDet, "_VICMS")) == "O"
                        cVlrICMS := AllTrim(oICMSDet:_VICMS:TEXT)
                        ConOut("Valor ICMS: " + cVlrICMS)
                    EndIf

                Else
                    ConOut("Nenhuma estrutura ICMS identificada")
                EndIf

            Else
                ConOut("Tag _ICMS não encontrada")
            EndIf
        EndIf


        // IPI - Note que no XML tem IPINT, não IPITRIB
        If ValType(XmlChildEx(oImp, "_IPI")) == "O"
            ConOut("Tag _IPI localizada")
            
            // Tenta IPINT (que está no XML)
            If ValType(XmlChildEx(oImp:_IPI, "_IPINT")) == "O"
                ConOut("Tag _IPINT localizada")
                // IPINT não tem alíquota de IPI no XML fornecido
            Else
                ConOut("Tag _IPINT não encontrada")
            EndIf
            
            // Tenta IPITRIB também
            If ValType(XmlChildEx(oImp:_IPI, "_IPITRIB")) == "O"
                ConOut("Tag _IPITRIB localizada")
                
                If ValType(XmlChildEx(oImp:_IPI:_IPITRIB, "_PIPI")) == "O"
                    cAliqIPI := AllTrim(oImp:_IPI:_IPITRIB:_PIPI:TEXT)
                    ConOut("Alíquota IPI: " + cAliqIPI)
                EndIf
            Else
                ConOut("Tag _IPITRIB não encontrada")
            EndIf
        Else
            ConOut("Tag _IPI não encontrada")
        EndIf
    Else
        ConOut("Tag _IMPOSTO não encontrada")
    EndIf

   aLinha := { ;
    cProd, ;        // [1] Produto
    cQtd, ;         // [2] Quantidade
    cVlrUnit, ;     // [3] Valor Unitário
    cDesc, ;        // [4] Desconto
    cVlrICMS, ;     // [5] Valor ICMS
    cBaseICMS, ;    // [6] Base ICMS
    cAliqICMS, ;    // [7] Alíquota ICMS
    cAliqIPI ;      // [8] Alíquota IPI
}

    ConOut("Item extraído com sucesso")
    ConOut("--- Fim extração de item ---")

Return aLinha


/*/{Protheus.doc} fReadLargeFile
Lê arquivo de qualquer tamanho usando FOpen/FRead/FClose
@type function
@param cFile, character, Caminho completo do arquivo
@return character, Conteúdo do arquivo
/*/
Static Function fReadLargeFile(cFile)
    Local cContent  := ""
    Local cBuffer   := ""
    Local nHandle   := 0
    Local nBytes    := 0
    Local nTamBloco := 65536  // 64 KB por bloco
    Local nTentativas := 0
    Local nMaxTent  := 3
    
    // Tenta abrir o arquivo (com retry)
    While nTentativas < nMaxTent
        nHandle := FOpen(cFile, 0)  // 0 = FO_READ (somente leitura)
        
        If nHandle != -1
            Exit
        EndIf
        
        nTentativas++
        ConOut("Tentativa " + cValToChar(nTentativas) + " de abrir arquivo falhou. FError: " + cValToChar(FError()))
        
        If nTentativas < nMaxTent
            Sleep(500)  // Aguarda meio segundo antes de tentar novamente
        EndIf
    EndDo
    
    If nHandle == -1
        ConOut("ERRO ao abrir arquivo: " + cFile)
        ConOut("FError: " + cValToChar(FError()))
        Return ""
    EndIf
    
    // Lê o arquivo em blocos
    While .T.
        cBuffer := Space(nTamBloco)
        nBytes  := FRead(nHandle, @cBuffer, nTamBloco)
        
        If nBytes <= 0
            Exit
        EndIf
        
        // Adiciona apenas os bytes lidos (remove espaços extras)
        cContent += SubStr(cBuffer, 1, nBytes)
        
        // Opcional: mostrar progresso para arquivos muito grandes
        // ConOut("Lidos: " + cValToChar(Len(cContent)) + " bytes...")
    EndDo
    
    // Fecha o arquivo
    FClose(nHandle)
    
    ConOut("Arquivo lido com sucesso: " + cValToChar(Len(cContent)) + " bytes")
    
Return cContent

/*/{Protheus.doc} fGetFileSize
Obtém o tamanho do arquivo em bytes (função auxiliar)
@type function
@param cFile, character, Caminho do arquivo
@return numeric, Tamanho em bytes
/*/
Static Function fGetFileSize(cFile)
    Local nHandle := FOpen(cFile, 0)
    Local nSize   := 0
    
    If nHandle != -1
        FSeek(nHandle, 0, 2)  // FS_END - Move para o final
        nSize := FSeek(nHandle, 0, 1)  // FS_RELATIVE - Retorna posição atual
        FClose(nHandle)
    EndIf
    
Return nSize

/** 
 *  Copyright (c) 1999~2017, Altibase Corp. and/or its affiliates. All rights reserved.
 *
 *  This program is free software: you can redistribute it and/or modify
 *  it under the terms of the GNU Affero General Public License, version 3,
 *  as published by the Free Software Foundation.
 *
 *  This program is distributed in the hope that it will be useful,
 *  but WITHOUT ANY WARRANTY; without even the implied warranty of
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 *  GNU Affero General Public License for more details.
 *
 *  You should have received a copy of the GNU Affero General Public License
 *  along with this program. If not, see <http://www.gnu.org/licenses/>.
 */
 
/***********************************************************************
 * $Id:$
 **********************************************************************/

/* ======================================================
   NAME
    iSQLScanLexer.l

   1.
    This file was created for BUG-41163 SET SQLP[ROMPT]

   DESCRIPTION
    �Է� ���� prompt���� ������ �ش��ϴ� ������ ġȯ�Ѵ�.
     - ���� ����: _CONNECT_IDENTIFIER, _DATE, _PRIVILEGE, _USER

   cf. prompt ���ڿ��� syntax �˻�� iSQLLexer.l���� �����ϰ�
       ���⿡���� ���� ġȯ�� �����Ѵ�.

   2.
    Rules starting with the <params> start condition were added 
    for BUG-41173 Passing Parameters through the START command.

 ====================================================== */

%option 8bit
%option caseless
%option nounput noyymore noyywrap
%option prefix="iSQLScanLexer"

%{
#include <idl.h>
#include <idn.h>
#include <utString.h>
#include <iSQL.h>
#include <iSQLProperty.h>
#include <iSQLExecuteCommand.h>
#include <iSQLHostVarMgr.h>
#include <iSQLCommand.h>
#include <iSQLProgOption.h>
#include <iSQLCompiler.h>

//#define _ISQL_DEBUG

extern iSQLExecuteCommand * gExecuteCommand;
extern iSQLCommand        * gCommand;
extern iSQLProperty         gProperty;
extern iSQLProgOption       gProgOption;
extern iSQLBufMgr         * gBufMgr;
extern iSQLCompiler       * gSQLCompiler;
extern iSQLSpool          * gSpool;
extern iSQLHostVarMgr       gHostVarMgr;

#define ISQL_STATE_UNDEFINED     9999

SChar   gSubstitutionValue[WORD_LEN];
SChar  *gNewPromptBufPtr;
UInt    gAllowVariable;
UInt   *gPromptRefreshFlag;
idBool  gInitFlag = ID_FALSE;

void initSqlPrompt();
void appendText(SChar *aValue);
void getConnectIdentifier();

/* BUG-41173 Passing Parameters through the START Command */
SChar  *gCommandBufPtr;
SChar  *gNewLinePtr;
SChar  *gOldLineBufPtr;
SChar   gOldLineBuf[COMMAND_LEN];
UInt    gLineNum;
idBool  gSubstituteFlag;

void initPassingParams();
void appendOldLine(SChar *aValue);
void appendCommandStr(SChar *aValue);

/* BUG-41724 */
IDE_RC addHostVar(SChar *aHostVar);

/*
 * BUGBUG
 * for some reason, ECHO was defined badly as 0000010
 * the suspects as the followings..
 * /usr/include/asm-i386/termbits.h:#define ECHO   0000010
 * /usr/include/asm-x86_64/termbits.h:#define ECHO 0000010
 * /usr/include/bits/termios.h:#define ECHO        0000010
 * So, I remove define of ECHO as the following for removing compiler warnings..
 * Then, flex can define ECHO correctly..
 */
#if defined(ECHO)
# undef ECHO
#endif

%}

%option stack

%x sqlp
%x allow_variable

%x params
%x hostvar
%x IN_COMMENT

%%

BEGIN(INITIAL);

<sqlp>[ \t]+        {
    yy_push_state(allow_variable);
    appendText(yytext);
}
<sqlp>["']        {
    gAllowVariable = !gAllowVariable;
    if (gAllowVariable == 1)
    {
        yy_push_state(allow_variable);
    }
}
<allow_variable>["']        {
    gAllowVariable = !gAllowVariable;
    if (gAllowVariable == 0)
    {
        yy_pop_state();
    }
}
<sqlp><<EOF>> {
    return IDE_SUCCESS;
}
<allow_variable><<EOF>> {
    yy_pop_state();
    return IDE_SUCCESS;
}
<allow_variable>_CONNECT_IDENTIFIER[._a-zA-Z0-9] {
    yy_pop_state();
    appendText(yytext);
}
<allow_variable>_DATE[._a-zA-Z0-9] {
    yy_pop_state();
    appendText(yytext);
}
<allow_variable>_PRIVILEGE[._a-zA-Z0-9] {
    yy_pop_state();
    appendText(yytext);
}
<allow_variable>_USER[._a-zA-Z0-9] {
    yy_pop_state();
    appendText(yytext);
}
<allow_variable>_CONNECT_IDENTIFIER {
    yy_pop_state();
    getConnectIdentifier();
    appendText(gSubstitutionValue);
}
<allow_variable>_DATE {
    yy_pop_state();
    gExecuteCommand->GetCurrentDate(gSubstitutionValue);
    appendText(gSubstitutionValue);
    *gPromptRefreshFlag = PROMPT_REFRESH_ON;
}
<allow_variable>_PRIVILEGE {
    yy_pop_state();
    if (gProperty.IsSysDBA() == ID_TRUE)
    {
        appendText((SChar *)"(sysdba)");
    }
    else
    {
        /* do nothing */
    }
    *gPromptRefreshFlag = *gPromptRefreshFlag | PROMPT_VARIABLE_ON;
}
<allow_variable>_USER {
    yy_pop_state();
    appendText(gProperty.GetUserName());
    *gPromptRefreshFlag = *gPromptRefreshFlag | PROMPT_VARIABLE_ON;
}
<sqlp>. {
    appendText(yytext);
}
<allow_variable>[ \t]+ {
    appendText(yytext);
}
<allow_variable>. {
    yy_pop_state();
    appendText(yytext);
}

<params>"&"[ \t]*[1-9][0-9]*[_a-zA-Z] {
    appendCommandStr(yytext);
    appendOldLine(yytext);
}
<params>"&"[ \t]*[1-9][0-9]*"."? {
    SChar *sVar    = NULL;
    SChar *sTmp    = NULL;
    SChar *sValue  = NULL;
    UInt   sVarIdx = 0;
    SChar  sTempVal[WORD_LEN];

    appendOldLine(yytext);

    sTmp = yytext;
    while ( *sTmp )
    {
        if (isdigit(*sTmp) != 0) // �����̸�...
        {
            sVar = sTmp;
            break;
        }
        sTmp++;
    }
    sTmp = yytext + yyleng - 1;
    while ( *sTmp )
    {
        if (isdigit(*sTmp) != 0) // �����̸�...
        {
            sTmp++;
            *sTmp = '\0';
            break;
        }
        sTmp--;
    }
    sVarIdx = idlOS::atoi(sVar);
    sValue = gSQLCompiler->GetPassingValue(sVarIdx);
    if (sValue == NULL)
    {
        idlOS::printf("Enter value for %s: ", sVar);
        idlOS::fflush(stdout);
        idlOS::gets(sTempVal, WORD_LEN);

        appendCommandStr(sTempVal);
    }
    else
    {
        appendCommandStr(sValue);
    }
    gSubstituteFlag = ID_TRUE;
}

<params>"\n"  {
    if (gSubstituteFlag == ID_TRUE && gProperty.GetVerify() == ID_TRUE )
    {
        idlOS::sprintf(gSpool->m_Buf, "old%4d: %s\n", gLineNum, gOldLineBuf);
        gSpool->Print();
        idlOS::sprintf(gSpool->m_Buf, "new%4d: %s\n", gLineNum, gNewLinePtr);
        gSpool->Print();
    }
    appendCommandStr(yytext);

    initPassingParams();
}
<params>. {
    appendCommandStr(yytext);
    appendOldLine(yytext);
}
<params><<EOF>> {
    *gCommandBufPtr = '\0';
    return IDE_SUCCESS;
}

<hostvar>":"[_A-Z][_0-9A-Z]* {
    IDE_RC sRet;

    sRet = addHostVar(yytext + 1);

    if (sRet != IDE_SUCCESS)
    {
        return IDE_FAILURE;
    }
}
<hostvar><<EOF>> {
    return IDE_SUCCESS;
}
<hostvar>[\r\n]
<hostvar>.
<hostvar>"\""[^'"]+"\""      /* BUG-30325: skip quoted string 
                        same as the TI_QUOTED_IDENTIFIER in qcpll.l */
<hostvar>"'"("''"*[^']*)*"'" /* BUG-30325: skip quoted string
                        same as the TL_LITERAL in qcpll.l */
<hostvar>"--"[^\n]*          /* BUG-30525: skip single line comment */
<hostvar>"//"[^\n]*          /* BUG-30525: skip single line comment */
<hostvar>{                   /* skip multi-line comment */
"/*"  BEGIN(IN_COMMENT);
}
<IN_COMMENT>{
"*/"      BEGIN(hostvar);
[^*\n]+   // eat comment in chunks
"*"       // eat the lone star
\r?\n     // yylineno++;
}

%%

/*
 * ���ڷ� ���� ���ڿ��� CommandBuf�� �߰�
 */
void appendCommandStr(SChar *aValue)
{
    while ( *aValue )
    {
        *gCommandBufPtr++ = *aValue++;
    }
    *gCommandBufPtr = '\0';
}

/*
 * ���ڷ� ���� ���ڿ��� OldLineBuf�� �߰�.
 */
void appendOldLine(SChar *aValue)
{
    while ( *aValue )
    {
        *gOldLineBufPtr++ = *aValue++;
    }
    *gOldLineBufPtr = '\0';
}

/*
 * ���ڷ� ���� ���ڿ��� NewPrompt ���ۿ� �߰�
 */
void appendText(SChar *aValue)
{
    while ( *aValue )
    {
        *gNewPromptBufPtr++ = *aValue++;
    }
    *gNewPromptBufPtr = '\0';
}

/*
 * _CONNECT_IDENTIFIER variable�� �����ϴ� ���� ���ؼ� �ӽ� ���ۿ� ����
 * NATC ����ÿ��� diff ������ ���� ������ ���ڿ� ��ȯ ^^;;
 */
void getConnectIdentifier()
{
    if (gProgOption.IsATC() == ID_TRUE)
    {
        idlOS::sprintf(gSubstitutionValue, "localhost:20300");
    }
    else
    {
        idlOS::snprintf(gSubstitutionValue, WORD_LEN,
                        "%s:%"ID_UINT32_FMT,
                        gProgOption.GetServerName(),
                        gProgOption.GetPortNo());
    }
}

/*
 * ���� �ʱ�ȭ �� start condition ����
 */
void initSqlPrompt()
{
    gSubstitutionValue[0] = '\0';
    gAllowVariable = 1;

    yy_push_state(sqlp);
    yy_push_state(allow_variable);
}

/*
 * ����� �Է� prompt �ؽ�Ʈ�� ��ĵ�Ͽ� ������ �ش��ϴ� ������ ġȯ�Ѵ�.
 *
 * aSqlPrompt    : �Է� prompt
 * aNewPromptBuf : ���� prompt�� ����� ����
 * aPromptRefreshFlag: ġȯ������ �����ϴ� ���, prompt�� ����� ������
 *                 prompt ���� ����� �� �ִ�.
 *                 �� ���� prompt�� �������� ����Ǿ�� �ϴ��� ���θ� ��ȯ�Ѵ�.
 *
 * return        : �Է� prompt text�� ��ȿ���� ���� ��� IDE_FAILURE ��ȯ.
 */
SInt lexSqlPrompt(const SChar *aSqlPrompt,
                  SChar       *aNewPromptBuf,
                  UInt        *aPromptRefreshFlag)
{
    /* lexer�� �Է��� stdin���� ���۷� ��ü */
    yy_switch_to_buffer(yy_scan_string(aSqlPrompt));

    gNewPromptBufPtr = aNewPromptBuf;
    gPromptRefreshFlag = aPromptRefreshFlag;

    initSqlPrompt();

    return iSQLScanLexerlex();
}

/***********************************************************
 * BUG-41173 Passing Parameters through the START command.
 ***********************************************************/
/*
 * ���� ����:
 * gCommandBuf: ġȯ������ ������ ġȯ�� ���ڿ��� ����ȴ�.
 * gOldLineBuf: ġȯ�Ǳ� ���� ���ڿ��� ���� ������ ����ȴ�.
 * gNewLinePtr: gCommandBuf���� �� ������ ���� ��ġ�� ����Ų��.
 */
void initPassingParams()
{
    gSubstituteFlag = ID_FALSE;
    gOldLineBuf[0]  = '\0';
    gOldLineBufPtr  = gOldLineBuf;
    gNewLinePtr     = gCommandBufPtr;
    gLineNum++;
}

/*
 * Description:
 *   ���� ���ڿ��� ��ĵ�ϸ鼭 &[num]���� ǥ�õ�
 *   substitution variable�� ã�Ƽ� ���޵� ������ ġȯ�Ѵ�.
 */
void lexSubstituteVars()
{
    SChar *sCommandStr   = NULL;

    /* ���� ����:
     * gBufMgr->GetBuf(): original sql text
     * sCommandStr: original sql text�� sCommandStr�� ������ ��,
     *              lexer�� input buffer�� ���
     * gCommandBufPtr: gBufMgr->GetBuf()�� �����ͷν�, ġȯ�� ������ ����
     */
    sCommandStr = (SChar *)idlOS::malloc(
                      idlOS::strlen(gBufMgr->GetBuf()) + 1);
    IDE_TEST(sCommandStr == NULL);

    idlOS::strcpy(sCommandStr, gBufMgr->GetBuf());

    /* lexer�� �Է��� stdin���� ���۷� ��ü */
    yy_switch_to_buffer(yy_scan_string(sCommandStr));

    gCommandBufPtr = gBufMgr->GetBuf();
    gLineNum = 0;

    initPassingParams();

    /* start condition ���� */
    yy_push_state(params);

    iSQLScanLexerlex();

    idlOS::free(sCommandStr);

    IDE_EXCEPTION_END;
}

IDE_RC addHostVar(SChar *aHostVar)
{
    IDE_TEST(utString::toUpper(aHostVar) != IDE_SUCCESS);
    IDE_TEST(gHostVarMgr.putBindList(aHostVar) != IDE_SUCCESS);

    return IDE_SUCCESS;

    IDE_EXCEPTION_END;

    return IDE_FAILURE;
}

/*
 * Description: BUG-41724
 *   stored proc/fuc ���� ������ ��ĵ�ϸ鼭 :var���� ǥ�õ�
 *   host variable�� bind list�� �ϼ��Ѵ�.
 */
SInt lexHostVariables(SChar *aBuf)
{
    /* lexer�� �Է��� stdin���� ���۷� ��ü */
    yy_switch_to_buffer(yy_scan_string(aBuf));

    /* start condition ���� */
    yy_push_state(hostvar);

    gHostVarMgr.initBindList();

    return iSQLScanLexerlex();
}

void preventCompileWarning()
{
    yy_top_state();
}
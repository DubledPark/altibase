/** 
 *  Copyright (c) 1999~2017, Altibase Corp. and/or its affiliates. All rights reserved.
 *
 *  This program is free software: you can redistribute it and/or modify
 *  it under the terms of the GNU Lesser General Public License, version 3,
 *  as published by the Free Software Foundation.
 *
 *  This program is distributed in the hope that it will be useful,
 *  but WITHOUT ANY WARRANTY; without even the implied warranty of
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 *  GNU Lesser General Public License for more details.
 *
 *  You should have received a copy of the GNU Lesser General Public License
 *  along with this program. If not, see <http://www.gnu.org/licenses/>.
 */
 
/***********************************************************************
 * $Id: idnCharMap.h 24174 2007-11-19 01:23:49Z copyrei $
 *
 * Description :
 *     gNlsCaseCharMap : uppercase, lowercase ��ȯ ����ǥ
 *
 *     uppercase/lowercase �����ڵ� ���� : U+0000 ~ U+2D26
 *
 **********************************************************************/

#ifndef _O_IDNCASECONVMAP_H_
#define _O_IDNCASECONVMAP_H_ 1

// 0x2D26 ������ �����ڵ忡 ���ؼ��� ��ҹ��� ��ȯ�� �ǹ̰� ����
#define IDN_NLS_CASE_UNICODE_MAX        (0x2D26)  /* 11558 */

typedef struct idnNlsCaseConvMap
{
    UShort      upper;
    UShort      lower;
} idnNlsCaseConvMap;

#endif /* _O_IDNCASECONVMAP_H_ */
 
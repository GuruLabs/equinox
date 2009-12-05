#!/usr/bin/python
# vim: set fileencoding=utf-8 : -*- coding: utf-8 -*-
# vim: set sw=4 ts=8 sts=4 expandtab autoindent :
# -*- tab-width 8 ; indent-tabs-mode: nil -*-

import doctest
import unittest

import equinox

suite = unittest.TestSuite()
suite.addTest(doctest.DocTestSuite(equinox, optionflags=doctest.ELLIPSIS))
runner = unittest.TextTestRunner()
runner.run(suite)

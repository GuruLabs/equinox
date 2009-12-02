# vim: set fileencoding=utf-8 : -*- coding: utf-8 -*-
# vim: set sw=4 ts=8 sts=4 expandtab autoindent :
# -*- tab-width 8 ; indent-tabs-mode: nil -*-

# TODO Raise exceptions on libxml2 errors

from python cimport PyString_Check, PyUnicode_Check, PyInt_Check
from python cimport PyObject_Type, PyObject_TypeCheck
from python_unicode cimport PyUnicode_DecodeUTF8

cdef extern from "string.h":
    size_t strlen(char *s)

cdef extern from "libxml/xmlstring.h":
    ctypedef unsigned char xmlChar

cdef extern from "libxml/parser.h":
    ctypedef enum xmlParserOption:
        XML_PARSE_NOENT = 2
        XML_PARSE_NONET = 2048
        XML_PARSE_NOCDATA = 16384

cdef extern from "libxml/xmlreader.h":
    ctypedef enum xmlReaderTypes:
        XML_READER_TYPE_ELEMENT = 1
        XML_READER_TYPE_ATTRIBUTE = 2
        XML_READER_TYPE_TEXT = 3
        XML_READER_TYPE_WHITESPACE = 13
        XML_READER_TYPE_SIGNIFICANT_WHITESPACE = 14
        XML_READER_TYPE_END_ELEMENT = 15

    ctypedef struct xmlTextReader:
        pass
    ctypedef xmlTextReader *xmlTextReaderPtr

    xmlTextReaderPtr xmlReaderForFile(char *filename,
                                      char *encoding,
                                      int options)
    void xmlFreeTextReader(xmlTextReaderPtr reader)

    int xmlTextReaderRead(xmlTextReaderPtr reader)

    int xmlTextReaderHasAttributes(xmlTextReaderPtr reader)
    bint xmlTextReaderHasValue(xmlTextReaderPtr reader)
    bint xmlTextReaderIsEmptyElement(xmlTextReaderPtr reader)
    int xmlTextReaderNodeType(xmlTextReaderPtr reader)

    char *xmlTextReaderConstLocalName(xmlTextReaderPtr reader)
    bint xmlTextReaderMoveToElement(xmlTextReaderPtr reader)
    bint xmlTextReaderMoveToFirstAttribute(xmlTextReaderPtr reader)
    bint xmlTextReaderMoveToNextAttribute(xmlTextReaderPtr reader)
    char *xmlTextReaderConstValue(xmlTextReaderPtr reader)

cdef extern from "libxml/xmlwriter.h":
    ctypedef struct xmlTextWriter:
        pass
    ctypedef xmlTextWriter *xmlTextWriterPtr

    xmlTextWriterPtr xmlNewTextWriterFilename(char *uri,
                                              bint compress)
    void xmlFreeTextWriter(xmlTextWriterPtr writer)

    int xmlTextWriterStartDocument(xmlTextWriterPtr writer,
                                   xmlChar *version,
                                   xmlChar *encoding,
                                   xmlChar *standalone)
    int xmlTextWriterEndDocument(xmlTextWriterPtr writer)
    int xmlTextWriterFlush(xmlTextWriterPtr writer)

    int xmlTextWriterStartElement(xmlTextWriterPtr writer,
                                  xmlChar *name)
    int xmlTextWriterEndElement(xmlTextWriterPtr writer)

    int xmlTextWriterWriteAttribute(xmlTextWriterPtr writer,
                                    xmlChar *name,
                                    xmlChar *content)

    int xmlTextWriterWriteCDATA(xmlTextWriterPtr writer,
                                xmlChar *content)
    int xmlTextWriterWriteString(xmlTextWriterPtr writer,
                                 xmlChar *content)

#--------------------------------------
# Helpers
#--------------------------------------
cdef unicode utf8_to_unicode(char* s):
    return PyUnicode_DecodeUTF8(s, strlen(s), 'strict')

# char *c_string = byte_string is just a pointer into byte_string's
# buffer so safe use of c_string depends on byte_string still being
# valid. For this reason we return a python byte string and require
# the caller to create a char* and keep it valid.
cdef str unicode_to_utf8(s):
    cdef str byte_string
    if isinstance(s, str):
        byte_string = s
    elif isinstance(s, str):
        byte_string = s.encode(u'UTF-8')
    else:
        byte_string = unicode(s).encode(u'UTF-8')
    return byte_string

#--------------------------------------
# Classes
#--------------------------------------
cdef class Node
cdef class Element(Node)
cdef class Text(Node)

cdef class Node:
    cdef Element _parent
    cdef Node _prev_sib
    cdef Node _next_sib

    # Properties
    property name:
        def __get__(self):
            return None

    property parent:
        def __get__(self):
            return self._parent

    property prev_sib:
        def __get__(self):
            return self._prev_sib

        def __set__(self, Node new_sib):
            if not new_sib:
                raise ValueError
            cdef Element parent = self._parent
            cdef Node old_sib = self._prev_sib
            new_sib._link(parent, old_sib, self)

    property next_sib:
        def __get__(self):
            return self._next_sib

        def __set__(self, Node new_sib):
            if not new_sib:
                raise ValueError
            cdef Element parent = self._parent
            cdef Node old_sib = self._next_sib
            new_sib._link(parent, self, old_sib)

    # Mutators
    cdef _link(self, Element parent, Node prev_sib, Node next_sib):
        assert(parent)
        self.unlink()
        self._parent = parent
        self._prev_sib = prev_sib
        self._next_sib = next_sib
        if prev_sib:
            prev_sib._next_sib = self
        else:
            parent._first_child = self
        if next_sib:
            next_sib._prev_sib = self
        else:
            parent._last_child = self

    cpdef replaceWith(Node self, Node replacement):
        self.prev_sib = replacement
        self.unlink()
            
    cpdef unlink(Node self):
        cdef Element parent = self._parent
        cdef Node prev_sib = self._prev_sib
        cdef Node next_sib = self._next_sib
        if prev_sib:
            prev_sib._next_sib = next_sib
        elif parent:
            assert(parent._first_child == self)
            parent._first_child = next_sib
        if next_sib:
            next_sib._prev_sib = prev_sib
        elif parent:
            assert(parent._last_child == self)
            parent._last_child = prev_sib
        self._parent = None
        self._prev_sib = None
        self._next_sib = None

cdef class NodeIterator:
    cdef Node _next_node

    def __cinit__(self, Node start_node):
        self._next_node = start_node

    def __next__(self):
        cdef Node node = self._next_node
        if node is None:
            raise StopIteration
        self._next_node = node._next_sib
        return node

cdef class Text(Node):
    cdef unicode _text

    def __cinit__(self, text, *args, **kwargs):
        self._text = unicode(text)

    def __repr__(self):
        return repr(self._text)

    def __unicode__(self):
        return self._text

    # Properties
    property text:
        def __get__(self):
            return self._text

        def __set__(self, text):
            self._text = unicode(text)

cdef class Element(Node):
    cdef unicode _name
    cdef dict _attrs
    cdef Node _first_child
    cdef Node _last_child

    def __cinit__(self, name, dict attrs=None, list children=None,
                  *args, **kwargs):
        self._name = unicode(name)
        self._attrs = {}
        if attrs is not None:
            for k, v in attrs.iteritems():
                k = unicode(k)
                v = unicode(v)
                self._attrs[k] = v
        cdef Node prev_sib
        if children:
            iter_children = iter(children)
            prev_sib = iter_children.next()
            self.first_child = prev_sib
            for child in iter_children:
                prev_sib.next_sib = child
                prev_sib = child

    def __repr__(self):
        return '<Element "%s" at 0x%x>' % (self.name, id(self))

    def __unicode__(self):
        result = [c.text for c in self if c.name is None]
        return u''.join(result)

    # Properties
    property name:
        def __get__(self):
            return self._name

        def __set__(self, name):
            if not name:
                raise ValueError("Invalid element name")
            self._name = unicode(name)

    property first_child:
        def __get__(self):
            return self._first_child

        def __set__(self, Node child):
            if not child:
                raise ValueError
            first_child = self._first_child
            if first_child:
                first_child.prev_sib = child
            else:
                assert(not self._last_child)
                child._link(self, None, None)

    property last_child:
        def __get__(self):
            return self._last_child

        def __set__(self, Node child):
            if not child:
                raise ValueError
            last_child = self._last_child
            if last_child:
                last_child.next_sib = child
            else:
                assert(not self._first_child)
                child._link(self, None, None)

    # Attributes
    def __contains__(self, k):
        return self._attrs.__contains__(k)

    def __delitem__(self, k):
        self._attrs.__delitem__(k)

    def __getitem__(self, k):
        return self._attrs.__getitem__(k)

    def __setitem__(self, k, v):
        self._attrs.__setitem__(k, v)

    def get(self, k, default=None):
        return self._attrs.get(k, default)

    def has_key(self, k):
        return self._attrs.has_key(k)

    def iteritems(self):
        return self._attrs.iteritems()

    # Children
    def __iter__(self):
        return NodeIterator(self._first_child)

    def first(self, name):
        pass

    def all(self, name):
        pass

#--------------------------------------
# Reader
#--------------------------------------
ctypedef enum nodeTypes:
    TYPE_ELEMENT = 1
    TYPE_ATTR = 2
    TYPE_TEXT = 3
    TYPE_WHITESPACE = 4
    TYPE_END_ELEMENT = 5

cdef int _xmlReadToNextNode(xmlTextReaderPtr c_reader):
    cdef int type
    while xmlTextReaderRead(c_reader) > 0:
        type = xmlTextReaderNodeType(c_reader)
        if type == XML_READER_TYPE_ELEMENT:
            return TYPE_ELEMENT
        elif type == XML_READER_TYPE_END_ELEMENT:
            return TYPE_END_ELEMENT
        elif type == XML_READER_TYPE_TEXT:
            return TYPE_TEXT
        elif type in [XML_READER_TYPE_WHITESPACE,
                      XML_READER_TYPE_SIGNIFICANT_WHITESPACE]:
            return TYPE_WHITESPACE
    return -1

cdef unicode _xmlReadName(xmlTextReaderPtr c_reader):
    assert(xmlTextReaderNodeType(c_reader) == XML_READER_TYPE_ELEMENT)
    return utf8_to_unicode(
                <char *>xmlTextReaderConstLocalName(c_reader)
           )

cdef dict _xmlReadAttrs(xmlTextReaderPtr c_reader):
    assert( xmlTextReaderNodeType(c_reader) == XML_READER_TYPE_ELEMENT )
    cdef dict result = {}
    while xmlTextReaderMoveToNextAttribute(c_reader) == 1:
        k = utf8_to_unicode(<char *>
                xmlTextReaderConstLocalName(c_reader)
            )
        v = utf8_to_unicode(<char *>
                xmlTextReaderConstValue(c_reader)
            )
        result[k] = v
    xmlTextReaderMoveToElement(c_reader)
    return result

cdef Text _xmlReadText(xmlTextReaderPtr c_reader):
    assert( xmlTextReaderNodeType(c_reader) in
            [XML_READER_TYPE_TEXT,
             XML_READER_TYPE_WHITESPACE,
             XML_READER_TYPE_SIGNIFICANT_WHITESPACE] )
    text = utf8_to_unicode( <char *>xmlTextReaderConstValue(c_reader) )
    return Text(text)

cdef list _xmlReadChildren(xmlTextReaderPtr c_reader, ignore_whitespace):
    assert(xmlTextReaderNodeType(c_reader) == XML_READER_TYPE_ELEMENT)

    cdef list result = []
    cdef int type = _xmlReadToNextNode(c_reader)
    while (type > 0) and (type != TYPE_END_ELEMENT):
        if type == TYPE_ELEMENT:
            result.append( _xmlReadTree(c_reader, ignore_whitespace) )
        elif type == TYPE_TEXT:
            result.append( _xmlReadText(c_reader) )
        elif type == TYPE_WHITESPACE:
            if not ignore_whitespace:
                result.append( _xmlReadText(c_reader) )
        else:
            assert(False)
        type = _xmlReadToNextNode(c_reader)

    if type != TYPE_END_ELEMENT:
        raise RuntimeError("Invalid XML file")

    return result

cdef Element _xmlReadTree(xmlTextReaderPtr c_reader, ignore_whitespace):
    assert(xmlTextReaderNodeType(c_reader) == XML_READER_TYPE_ELEMENT)

    cdef unicode name = _xmlReadName(c_reader)
    cdef dict attrs = _xmlReadAttrs(c_reader)
    cdef list children = None

    if xmlTextReaderIsEmptyElement(c_reader) == 0:
        children = _xmlReadChildren(c_reader, ignore_whitespace)

    return Element(name, attrs, children)

cpdef Element readXML(filename, ignore_whitespace=False):
    if not filename:
        raise RuntimeError("Invalid filename")

    py_filename = unicode_to_utf8(filename)
    cdef char *c_filename = py_filename
    cdef xmlTextReaderPtr c_reader
    c_reader = xmlReaderForFile(c_filename, NULL, XML_PARSE_NONET
                                                  | XML_PARSE_NOENT
                                                  | XML_PARSE_NOCDATA)

    cdef int type = _xmlReadToNextNode(c_reader)
    while (type > 0) and (type != TYPE_ELEMENT):
        type = _xmlReadToNextNode(c_reader)

    if type != TYPE_ELEMENT:
        raise RuntimeError("Invalid XML file")

    cdef Element tree = _xmlReadTree(c_reader, ignore_whitespace)
    xmlFreeTextReader(c_reader)
    return tree

#--------------------------------------
# Writer
#--------------------------------------
cdef _xmlWriteAttribute(xmlTextWriterPtr c_writer, name, value):
    py_name = unicode_to_utf8(name)
    cdef char *c_name = py_name
    py_value = unicode_to_utf8(value)
    cdef char *c_value = py_value
    xmlTextWriterWriteAttribute(c_writer, <xmlChar*>c_name, <xmlChar*>c_value)

cdef _xmlWriteText(xmlTextWriterPtr c_writer, text):
    py_text = unicode_to_utf8(text)
    cdef char *c_text = py_text
    xmlTextWriterWriteString(c_writer, <xmlChar*>c_text)

cdef _xmlWriteElement(xmlTextWriterPtr c_writer, element):
    py_name = unicode_to_utf8(element.name)
    cdef char *c_name = py_name
    xmlTextWriterStartElement(c_writer, <xmlChar*>c_name)
    for name, value in element.iteritems():
        _xmlWriteAttribute(c_writer, name, value)
    for child in element:
        if hasattr(child, 'iteritems'):
            _xmlWriteElement(c_writer, child)
        else:
            _xmlWriteText(c_writer, child)
    xmlTextWriterEndElement(c_writer)

cpdef writeXML(filename, tree):
    if not filename:
        raise RuntimeError("Invalid filename")

    py_filename = unicode_to_utf8(filename)
    cdef char *c_filename = py_filename
    cdef xmlTextWriterPtr c_writer
    c_writer = xmlNewTextWriterFilename(c_filename, 0)

    xmlTextWriterStartDocument(c_writer, NULL, NULL, NULL)
    _xmlWriteElement(c_writer, tree)
    xmlTextWriterEndDocument(c_writer)
    xmlFreeTextWriter(c_writer)

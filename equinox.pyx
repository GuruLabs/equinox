# vim: set fileencoding=utf-8 : -*- coding: utf-8 -*-
# vim: set sw=4 ts=8 sts=4 expandtab autoindent :
# -*- tab-width 8 ; indent-tabs-mode: nil -*-

__all__ = ('engine', 'read_xml', 'write_xml',
           'Element', 'Text', 'StructureError')

"""
A simplified interface to XML and other structured documents

>>> from equinox import Element, Text
>>> root = Element('foo',
...                attrs={'bar': 'baz',
...                       'qux': 'quux',
...                      },
...                children=[Element('corge'),
...                          Text('grault'),
...                          Element('garply'),
...                         ])
>>> root
<Element 'foo' at 0x...>
>>> root.name
u'foo'
>>> root['bar']
u'baz'
>>> root['qux']
u'quux'
>>> root.get('qux')
u'quux'
>>> root.get('quux')
>>> for child in root:
...     print repr(child)
<Element 'corge' at 0x...>
<Text u'grault'>
<Element 'garply' at 0x...>
>>> root.first_child
<Element 'corge' at 0x...>
>>> root.first_child.next_sib
<Text u'grault'>
>>> root.last_child
<Element 'garply' at 0x...>
"""

# TODO Raise exceptions on libxml2 errors

from cpython cimport bool
from cpython cimport PyString_Check, PyUnicode_Check, PyInt_Check
from cpython cimport PyObject_Type, PyObject_TypeCheck
from cpython.unicode cimport PyUnicode_DecodeUTF8

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
# Forward Declarations
#--------------------------------------
# Tree
cdef class Node
cdef class Element(Node)
cdef class Text(Node)
# Iterators
cdef class NodeIterator
cdef class ElementIterator
cdef class TextIterator
# Selectors
cdef class SelectorEngine

#--------------------------------------
# Globals
#--------------------------------------
engine = SelectorEngine()

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
    if isinstance(s, unicode):
        byte_string = s.encode(u'UTF-8')
    else:
        byte_string = unicode(s).encode(u'UTF-8')
    return byte_string

cdef Node object_as_node(object obj):
    cdef Node node
    if not obj:
        raise ValueError
    elif isinstance(obj, Node):
        node = obj
    elif isinstance(obj, str) or isinstance(obj, unicode):
        node = Text(obj)
    else:
        raise ValueError
    return node

#--------------------------------------
# Classes
#--------------------------------------
cdef class Node:
    cdef object _meta
    cdef Element _parent
    cdef Node _prev_sib
    cdef Node _next_sib

    cpdef Node __copy__(self):
        raise NotImplemented

    def __deepcopy__(self, memo):
        raise NotImplemented

    # Properties
    property meta:
        def __get__(self):
            cdef Element tmp
            if self._meta is not None:
                return self._meta
            else:
                tmp = self._parent
                while tmp:
                    if tmp._meta is not None:
                        return tmp._meta
                    tmp = tmp._parent
            return None

        def __set__(self, meta):
            self._meta = meta

    property name:
        def __get__(self):
            return None

    property parent:
        def __get__(self):
            return self._parent

    property prev_sib:
        def __get__(self):
            return self._prev_sib

    property next_sib:
        def __get__(self):
            return self._next_sib

    # Methods
    def copy(self):
        return self.__copy__()

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

    cpdef prepend_sibling(self, node):
        """
        prepend_sibling(self, node)

        >>> from equinox import Element, Text
        >>> node = Element('qux')
        >>> node.prev_sib
        >>> node.prepend_sibling('baz')
        Traceback (most recent call last):
          ...
        StructureError: ...
        >>> root = Element('rfc3092', children=[node])
        >>> node.prepend_sibling('foo')
        >>> node.prev_sib
        <Text u'foo'>
        >>> node.prepend_sibling(Element('bar'))
        >>> node.prepend_sibling(Text('baz'))
        >>> for child in root:
        ...     print child
        <Text u'foo'>
        <Element 'bar' at 0x...>
        <Text u'baz'>
        <Element 'qux' at 0x...>
        """
        cdef Node new_sib = object_as_node(node)
        cdef Node old_sib = self._prev_sib
        cdef Element parent = self._parent
        if not parent:
            raise StructureError("Node parent required")
        new_sib._link(parent, old_sib, self)

    cpdef append_sibling(self, node):
        """
        append_sibling(self, node)

        >>> from equinox import Element, Text
        >>> node = Element('foo')
        >>> node.next_sib
        >>> node.append_sibling('qux')
        Traceback (most recent call last):
          ...
        StructureError: ...
        >>> root = Element('rfc3092', children=[node])
        >>> node.append_sibling('qux')
        >>> node.next_sib
        <Text u'qux'>
        >>> node.append_sibling(Element('baz'))
        >>> node.append_sibling(Text('bar'))
        >>> for child in root:
        ...     print child
        <Element 'foo' at 0x...>
        <Text u'bar'>
        <Element 'baz' at 0x...>
        <Text u'qux'>
        """
        cdef Node new_sib = object_as_node(node)
        cdef Node old_sib = self._next_sib
        cdef Element parent = self._parent
        if not parent:
            raise StructureError("Node parent required")
        new_sib._link(parent, self, old_sib)

    cpdef substitute(Node self, Node replacement):
        """
        substitute(self, replacement)

        >>> from equinox import Element, Text
        >>> parent = Element('foo')
        >>> child = Element('bar')
        >>> parent.prepend(child)
        >>> print parent.first_child
        <Element 'bar' at 0x...>
        >>> child.substitute(Element('baz'))
        >>> print parent.first_child
        <Element 'baz' at 0x...>
        """
        self.prepend_sibling(replacement)
        self.unlink()

    cpdef unlink(Node self):
        """
        unlink(self)

        >>> from equinox import Element, Text
        >>> parent = Element('foo')
        >>> child = Element('bar')
        >>> parent.prepend(child)
        >>> print parent.first_child
        <Element 'bar' at 0x...>
        >>> child.unlink()
        >>> print parent.first_child
        None
        """
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

cdef class Text(Node):
    cdef unicode _text

    def __cinit__(self, text, *args, **kwargs):
        self._text = unicode(text)

    def __repr__(self):
        return '<Text %s>' % repr(self._text)

    def __unicode__(self):
        return self._text

    cpdef Node __copy__(self):
        return Text(self._text)

    def __deepcopy__(self, memo):
        return self.__copy__()

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
                self._attrs[k] = v
        cdef Node prev_sib
        if children:
            iter_children = iter(children)
            prev_sib = iter_children.next()
            self.prepend(prev_sib)
            for child in iter_children:
                prev_sib.append_sibling(child)
                prev_sib = child

    cpdef Node __copy__(self):
        cdef Element copy = Element(self._name)
        copy._attrs = self._attrs.copy()
        cdef Node prev_sib
        cdef Node next_sib
        cdef Node child = self._first_child
        if child is not None:
            prev_sib = child.__copy__()
            copy.prepend(prev_sib)
            child = child._next_sib
            while child is not None:
                next_sib = child.__copy__()
                prev_sib.append_sibling(next_sib)
                prev_sib = next_sib
                child = child._next_sib
        return copy

    def __deepcopy__(self, memo):
        return self.__copy__()

    def __repr__(self):
        return "<Element '%s' at 0x%x>" % (self.name, id(self))

    cdef list _text_leaves(self):
        cdef list result = []
        cdef Text tmp_t
        cdef Element tmp_e
        cdef Node child = self._first_child
        while child is not None:
            if child.name is None:
                tmp_t = child
                result.append(tmp_t._text)
            else:
                tmp_e = child
                result.extend(tmp_e._text_leaves())
            child = child._next_sib
        return result

    def __unicode__(self):
        return u''.join(self._text_leaves())

    # Properties
    property name:
        def __get__(self):
            return self._name

        def __set__(self, name):
            if not name:
                raise ValueError("Invalid element name")
            self._name = unicode(name)

    property text:
        """
        TODO

        >>> from equinox import Element, Text
        >>> e = Element('rfc3092', children=[
        ...          Element('metasyntactic-variable', children=[Text('foo')]),
        ...          Text(' '),
        ...          Element('metasyntactic-variable', children=[Text('bar')])
        ...     ])
        >>> e.text
        u'foo bar'
        """
        def __get__(self):
            return unicode(self)

    # Attributes
    def __contains__(self, k):
        k = unicode(k)
        return self._attrs.__contains__(k)

    def __delitem__(self, k):
        k = unicode(k)
        self._attrs.__delitem__(k)

    def __getitem__(self, k):
        k = unicode(k)
        return self._attrs.__getitem__(k)

    def __setitem__(self, k, v):
        k = unicode(k)
        self._attrs.__setitem__(k, v)

    def getattr(self, k, default=None):
        k = unicode(k)
        return self._attrs.get(k, default)

    get = getattr

    def has_attr(self, k):
        k = unicode(k)
        return self._attrs.has_key(k)

    has_key = has_attr

    def attrs(self):
        return self._attrs.items()

    items = attrs

    def iterattrs(self):
        return self._attrs.iteritems()

    iteritems = iterattrs

    # Children
    def __iter__(self):
        return NodeIterator(self)

    def iter(self, reversed=False):
        return NodeIterator(self, reversed)

    def iterelements(self, reversed=False):
        return ElementIterator(self, reversed)

    def itertexts(self, reversed=False):
        return TextIterator(self, reversed)

    property first_child:
        def __get__(self):
            return self._first_child

    property last_child:
        def __get__(self):
            return self._last_child

    # Methods
    cpdef prepend(self, node):
        """
        prepend(self, node)

        >>> from equinox import Element, Text
        >>> root = Element('rfc3092')
        >>> root.first_child
        >>> root.prepend(Text('baz'))
        >>> root.first_child
        <Text u'baz'>
        >>> root.prepend(Element('br'))
        >>> root.prepend(u'bar')
        >>> root.prepend(Element('br'))
        >>> root.prepend('foo')
        >>> for child in root:
        ...     print child
        <Text u'foo'>
        <Element 'br' at 0x...>
        <Text u'bar'>
        <Element 'br' at 0x...>
        <Text u'baz'>
        """
        cdef Node child = object_as_node(node)
        first_child = self._first_child
        if first_child:
            first_child.prepend_sibling(child)
        else:
            assert(not self._last_child)
            child._link(self, None, None)

    # TODO prepend_element(name, attrs, children)
    # TODO prepend_text(text)

    cpdef append(self, node):
        """
        append(self, node)

        >>> from equinox import Element, Text
        >>> root = Element('rfc3092')
        >>> root.last_child
        >>> root.append(Text('foo'))
        >>> root.last_child
        <Text u'foo'>
        >>> root.append(Element('br'))
        >>> root.append(u'bar')
        >>> root.append(Element('br'))
        >>> root.append(u'baz')
        >>> for child in root:
        ...     print child
        <Text u'foo'>
        <Element 'br' at 0x...>
        <Text u'bar'>
        <Element 'br' at 0x...>
        <Text u'baz'>
        """
        cdef Node child = object_as_node(node)
        last_child = self._last_child
        if last_child:
            last_child.append_sibling(child)
        else:
            assert(not self._first_child)
            child._link(self, None, None)

    # TODO append_element(name, attrs, children)
    # TODO append_text(text)

    cpdef Element first(self, name):
        """
        first(self, name)

        >>> root = Element('rfc3092', children=[
        ...                Element('foo', {'bar': 'baz'}),
        ...                Element('foo', {'qux': 'quux'}),
        ...        ])
        >>> child = root.first('foo')
        >>> child['bar']
        'baz'
        >>> child['qux']
        Traceback (most recent call last):
          ...
        KeyError: u'qux'
        """
        return engine.first(name, self)

    cpdef Element last(self, name):
        """
        last(self, name)

        >>> root = Element('rfc3092', children=[
        ...                Element('foo', {'bar': 'baz'}),
        ...                Element('foo', {'qux': 'quux'}),
        ...        ])
        >>> child = root.last('foo')
        >>> child['bar']
        Traceback (most recent call last):
          ...
        KeyError: u'bar'
        >>> child['qux']
        'quux'
        """
        return engine.last(name, self)

    cpdef list all(self, name):
        """
        all(self, name)

        >>> root = Element('rfc3092', children=[
        ...                Element('foo', {'bar': 'baz'}),
        ...                Element('foo', {'qux': 'quux'}),
        ...        ])
        >>> root.all('foo')
        [<Element 'foo' at 0x...>, <Element 'foo' at 0x...>]
        >>> root.all('corge')
        []
        """
        return engine.all(name, self)

cdef class NodeIterator:
    cdef Node _next_node
    cdef bool _reversed

    def __cinit__(self, Element parent, bool reversed=False):
        if reversed:
            self._next_node = parent._last_child
        else:
            self._next_node = parent._first_child
        self._reversed = reversed

    def __next__(self):
        cdef Node node = self._next_node
        if node is None:
            raise StopIteration
        if self._reversed:
            self._next_node = node._prev_sib
        else:
            self._next_node = node._next_sib
        return node

    def __iter__(self):
        return self

cdef class ElementIterator:
    cdef Node _next_node
    cdef bool _reversed

    def __cinit__(self, Element parent, bool reversed=False):
        cdef Node start_node
        if reversed:
            start_node = parent._last_child
            while (start_node is not None) and (start_node.name is None):
                start_node = start_node._prev_sib
        else:
            start_node = parent._first_child
            while (start_node is not None) and (start_node.name is None):
                start_node = start_node._next_sib
        self._next_node = start_node
        self._reversed = reversed

    def __next__(self):
        cdef Node next_node
        cdef Node node = self._next_node
        if node is None:
            raise StopIteration
        if self._reversed:
            next_node = node._prev_sib
            while (next_node is not None) and (next_node.name is None):
                next_node = next_node._prev_sib
        else:
            next_node = node._next_sib
            while (next_node is not None) and (next_node.name is None):
                next_node = next_node._next_sib
        self._next_node = next_node
        return node

    def __iter__(self):
        return self

cdef class TextIterator:
    cdef Node _next_node
    cdef bool _reversed

    def __cinit__(self, Element parent, bool reversed=False):
        cdef Node start_node
        if reversed:
            start_node = parent._last_child
            while (start_node is not None) and (start_node.name is not None):
                start_node = start_node._prev_sib
        else:
            start_node = parent._first_child
            while (start_node is not None) and (start_node.name is not None):
                start_node = start_node._next_sib
        self._next_node = start_node
        self._reversed = reversed

    def __next__(self):
        cdef Node next_node
        cdef Node node = self._next_node
        if node is None:
            raise StopIteration
        if self._reversed:
            next_node = node._prev_sib
            while (next_node is not None) and (next_node.name is not None):
                next_node = next_node._prev_sib
        else:
            next_node = node._next_sib
            while (next_node is not None) and (next_node.name is not None):
                next_node = next_node._next_sib
        self._next_node = next_node
        return node

    def __iter__(self):
        return self

cdef class SelectorEngine:
    cdef dict _handlers

    def __cinit__(self):
        self._handlers = {}

    def register(self, query, fn):
        query = unicode(query)
        self._handlers[query] = fn

    cpdef Element first(self, query, Element element):
        """
        first(query, element)

        >>> def odd(parent, reversed):
        ...     for i, n in enumerate(parent.iter(reversed)):
        ...         if i%2:
        ...             yield n
        >>> engine = SelectorEngine()
        >>> engine.register(':odd', odd)
        >>> root = Element('rfc3092', children=[
        ...                Element('foo'),
        ...                Element('bar'),
        ...                Element('baz'),
        ...                Element('qux'),
        ...        ])
        >>> engine.first(':odd', root)
        <Element 'bar' at 0x...>
        """
        cdef Node child
        query = unicode(query)
        fn = self._handlers.get(query)
        if fn:
            return fn(element, False).next()
        else:
            child = element._first_child
            while child:
                if child.name == query:
                    return child
                else:
                    child = child._next_sib
            return None

    cpdef Element last(self, query, Element element):
        """
        last(query, element)

        >>> def odd(parent, reversed):
        ...     for i, n in enumerate(parent.iter(reversed)):
        ...         if i%2:
        ...             yield n
        >>> engine = SelectorEngine()
        >>> engine.register(':odd', odd)
        >>> root = Element('rfc3092', children=[
        ...                Element('foo'),
        ...                Element('bar'),
        ...                Element('baz'),
        ...                Element('qux'),
        ...        ])
        >>> engine.last(':odd', root)
        <Element 'baz' at 0x...>
        """
        cdef Node child
        query = unicode(query)
        fn = self._handlers.get(query)
        if fn:
            return fn(element, True).next()
        else:
            child = element._last_child
            while child:
                if child.name == query:
                    return child
                else:
                    child = child._prev_sib
            return None

    cpdef list all(self, query, Element element):
        """
        all(query, element)

        >>> def odd(parent, reversed):
        ...     for i, n in enumerate(parent.iter(reversed)):
        ...         if i%2:
        ...             yield n
        >>> engine = SelectorEngine()
        >>> engine.register(':odd', odd)
        >>> root = Element('rfc3092', children=[
        ...                Element('foo'),
        ...                Element('bar'),
        ...                Element('baz'),
        ...                Element('qux'),
        ...        ])
        >>> engine.all(':odd', root)
        [<Element 'bar' at 0x...>, <Element 'qux' at 0x...>]
        """
        cdef Node child
        cdef list result
        query = unicode(query)
        fn = self._handlers.get(query)
        if fn:
            return list(fn(element, False))
        else:
            child = element._first_child
            result = []
            while child:
                if child.name == query:
                    result.append(child)
                child = child._next_sib
            return result

class StructureError(Exception):
    pass

#--------------------------------------
# XML Reader
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

cpdef Element read_xml(filename, ignore_whitespace=False):
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
# XML Writer
#--------------------------------------
cdef _xmlWriteAttribute(xmlTextWriterPtr c_writer, name, value):
    py_name = unicode_to_utf8(name)
    cdef char *c_name = py_name
    py_value = unicode_to_utf8(unicode(value))
    cdef char *c_value = py_value
    xmlTextWriterWriteAttribute(c_writer, <xmlChar*>c_name, <xmlChar*>c_value)

cdef _xmlWriteText(xmlTextWriterPtr c_writer, text):
    py_text = unicode_to_utf8(text)
    cdef char *c_text = py_text
    xmlTextWriterWriteString(c_writer, <xmlChar*>c_text)

cdef _xmlWriteElement(xmlTextWriterPtr c_writer, Element element):
    py_name = unicode_to_utf8(element.name)
    cdef char *c_name = py_name
    xmlTextWriterStartElement(c_writer, <xmlChar*>c_name)
    for name, value in element.iterattrs():
        _xmlWriteAttribute(c_writer, name, value)
    for child in element:
        if hasattr(child, 'iterattrs'):
            _xmlWriteElement(c_writer, child)
        else:
            _xmlWriteText(c_writer, child)
    xmlTextWriterEndElement(c_writer)

cpdef write_xml(filename, tree):
    if not filename:
        raise RuntimeError("Invalid filename")
    if not isinstance(tree, Element):
        raise TypeError("Not an equinox tree")

    py_filename = unicode_to_utf8(filename)
    cdef char *c_filename = py_filename
    cdef xmlTextWriterPtr c_writer
    c_writer = xmlNewTextWriterFilename(c_filename, 0)

    xmlTextWriterStartDocument(c_writer, NULL, NULL, NULL)
    _xmlWriteElement(c_writer, tree)
    xmlTextWriterEndDocument(c_writer)
    xmlFreeTextWriter(c_writer)

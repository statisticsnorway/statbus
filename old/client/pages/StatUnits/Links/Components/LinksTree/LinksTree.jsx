import React, { useState, useEffect } from 'react'
import { func, shape } from 'prop-types'
import Tree from 'antd/lib/tree'
import { Loader } from 'semantic-ui-react'
import { equals } from 'ramda'
import UnitNode from './UnitNode.jsx'

const patchTree = (tree, node, children) => {
  const dfs = nodes =>
    nodes.map((n) => {
      if (node.id === n.id && node.type === n.type) {
        return { ...n, children: children.map(v => ({ ...v, children: null })) }
      } else if (n.children !== null) {
        return { ...n, children: dfs(n.children) }
      }
      return n
    })
  return dfs(tree)
}

const getExpandedKeys = (tree) => {
  const expandedKeys = new Set()
  const dfs = (nodes) => {
    nodes.forEach((item) => {
      if (item.children === null) return
      expandedKeys.add(`${item.id}-${item.type}`)
      dfs(item.children)
    })
  }
  dfs(tree)
  return [...expandedKeys]
}

const filterTreeNode = node => node.props.node.highlight

function LinksTree({ filter, localize, getUnitsTree, getUnitLinks, getNestedLinks }) {
  const [tree, setTree] = useState([])
  const [selectedKeys, setSelectedKeys] = useState([])
  const [expandedKeys, setExpandedKeys] = useState([])
  const [links, setLinks] = useState([])
  const [isLoading, setIsLoading] = useState(undefined)

  useEffect(() => {
    fetchUnitsTree(filter)
  }, [filter])

  const onLoadData = ({ props: { node } }) =>
    node.children !== null
      ? new Promise((resolve) => {
        resolve()
      })
      : getNestedLinks({ id: node.id, type: node.type })
        .then((resp) => {
          setTree(prevTree => patchTree(prevTree, node, resp))
          setExpandedKeys(prevExpandedKeys =>
            resp.length === 0
              ? prevExpandedKeys.filter(v => v !== `${node.id}-${node.type}`)
              : prevExpandedKeys)
        })
        .catch(() => {
          setExpandedKeys(prevExpandedKeys =>
            prevExpandedKeys.filter(v => v !== `${node.id}-${node.type}`))
        })

  const onSelect = (
    keys,
    {
      node: {
        props: {
          node: { id, type },
        },
      },
    },
  ) => {
    setSelectedKeys(keys)
    setLinks([])
    window.open(`/statunits/view/${type}/${id}`, '_blank')
  }

  const onExpand = (newExpandedKeys) => {
    setExpandedKeys(newExpandedKeys)
  }

  const fetchUnitsTree = (filter) => {
    setIsLoading(true)
    getUnitsTree(filter)
      .then((resp) => {
        setTree(resp)
        setExpandedKeys(getExpandedKeys(resp))
        setSelectedKeys([])
        setLinks([])
        setIsLoading(false)
      })
      .catch(() => {
        setTree([])
        setIsLoading(false)
      })
  }

  const renderChildren = nodes =>
    nodes.map((node) => {
      const props = {
        key: `${node.id}-${node.type}`,
        title: <UnitNode localize={localize} {...node} />,
        node,
      }
      if (node.children !== null) {
        if (node.children.length === 0) props.isLeaf = true
        else props.children = renderChildren(node.children)
      }
      return <Tree.TreeNode {...props} />
    })

  return isLoading ? (
    <Loader active inline="centered" />
  ) : (
    <div>
      {tree.length !== 0 && (
        <Tree
          autoExpandParent={false}
          selectedKeys={selectedKeys}
          expandedKeys={expandedKeys}
          onSelect={onSelect}
          onExpand={onExpand}
          filterTreeNode={filterTreeNode}
          loadData={onLoadData}
        >
          {renderChildren(tree)}
        </Tree>
      )}
    </div>
  )
}

LinksTree.propTypes = {
  filter: shape({}).isRequired,
  localize: func.isRequired,
  getUnitsTree: func.isRequired,
  getUnitLinks: func.isRequired,
  getNestedLinks: func.isRequired,
}

export default LinksTree

import React from 'react'
import { shape, arrayOf } from 'prop-types'
import Tree from 'antd/lib/tree'

const { TreeNode } = Tree

const generateHyperlink = (title, url) => (url === null ? <a href={url}>{title}</a> : title)

const buildSubtree = (parent, tree) => {
  const children = tree.filter(c => c.parentNodeId === parent.id)
  return (
    <TreeNode
      selectable
      title={generateHyperlink(parent.title, parent.reportUrl)}
      url={parent.reportUrl}
      key={parent.id}
    >
      {children.length ? children.map(x => buildSubtree(x, tree)) : null}
    </TreeNode>
  )
}

const buildTree = (parents, dataTree) => parents.map(x => buildSubtree(x, dataTree))

const onSelect = (keys, { node: { props } }) => {
  window.open(props.url, '_blank')
}

const ReportsTree = ({ dataTree }) => {
  const tree = buildTree(dataTree.filter(x => x.parentNodeId === null), dataTree)
  return (
    <div>
      <Tree defaultExpandAll onSelect={onSelect}>
        {tree}
      </Tree>
    </div>
  )
}

ReportsTree.propTypes = {
  dataTree: arrayOf(shape({})).isRequired,
}

export default ReportsTree

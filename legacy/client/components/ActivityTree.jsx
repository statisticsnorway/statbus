import React from 'react'
import { func, string, arrayOf, shape, bool } from 'prop-types'
import Tree from 'antd/lib/tree'
import { Loader } from 'semantic-ui-react'

import { getNewName } from 'helpers/locale.js'

const { TreeNode } = Tree

export const transform = x => ({
  ...x,
  name: getNewName(x, true),
})

const buildSubtree = (parent, tree) => {
  const children = tree.filter(c => c.parentId === parent.id)
  return (
    <TreeNode title={parent.name} key={parent.id}>
      {children.length ? children.map(x => buildSubtree(x, tree)) : null}
    </TreeNode>
  )
}

const buildTree = (parents, dataTree) => parents.map(x => buildSubtree(x, dataTree))

const onLoadData = loadNode => (node) => {
  const key = node.props.eventKey
  if (key !== 'all') {
    loadNode(key)
  }
  return new Promise((resolve) => {
    resolve()
  })
}

const ActivityTree = ({
  dataTree,
  localize,
  name,
  label,
  checked,
  callBack,
  loadNode,
  loaded,
  disabled,
}) => {
  const tree = buildTree(
    dataTree.filter(x => x.parentId === 0).map(transform),
    dataTree.map(transform),
  )
  return (
    <div>
      <label htmlFor={name}>{localize(label)}</label>
      <br />
      {loaded ? (
        <Tree
          checkable
          disabled={disabled}
          checkedKeys={checked}
          onCheck={callBack}
          loadData={onLoadData(loadNode)}
        >
          <TreeNode title={localize('AllActivities')} key="all">
            {tree}
          </TreeNode>
        </Tree>
      ) : (
        <Loader inline active size="small" />
      )}
    </div>
  )
}

ActivityTree.propTypes = {
  localize: func.isRequired,
  callBack: func.isRequired,
  name: string.isRequired,
  label: string.isRequired,
  dataTree: arrayOf(shape({})).isRequired,
  checked: arrayOf(string),
  loadNode: func.isRequired,
  loaded: bool,
  disabled: bool,
}

ActivityTree.defaultProps = {
  checked: [],
  loaded: true,
  disabled: false,
}

export default ActivityTree

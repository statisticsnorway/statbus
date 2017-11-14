import React from 'react'
import { func, string, arrayOf, shape } from 'prop-types'
import Tree from 'antd/lib/tree'

const TreeNode = Tree.TreeNode

function buildTree(parrents, childrens) {
  return parrents.map((p) => {
    const nodes = childrens
      .filter(c => c.code.substr(0, 1).match(p.code))
      .map(c => <TreeNode title={c.name} key={`${c.id}`} />)
    return (
      <TreeNode title={p.name} key={`${p.id}`}>
        {nodes.length ? nodes : null}
      </TreeNode>
    )
  })
}

const ActivityTree = ({ dataTree, localize, name, label, checked, callBack }) => {
  const getNodes = regexp => dataTree.filter(x => x.code.match(regexp))
  const tree = buildTree(getNodes(/^[a-z]$/i), getNodes(/^[a-z]{2}$/i))
  return (
    <div>
      <label htmlFor={name}>{localize(label)}</label>
      <Tree checkable checkedKeys={checked} onCheck={callBack}>
        <TreeNode title={localize('AllActivities')} key="all">
          {tree}
        </TreeNode>
      </Tree>
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
}

ActivityTree.defaultProps = {
  checked: [],
}

export default ActivityTree

import React from 'react'
import { string, arrayOf, shape, bool, func } from 'prop-types'
import { Loader } from 'semantic-ui-react'
import Tree from 'antd/lib/tree'

import { transform } from './ActivityTree.jsx'
import { getNewName } from 'helpers/locale.js'
import styles from './styles.scss'

const { TreeNode } = Tree

class RegionTree extends React.Component {
  static propTypes = {
    name: string.isRequired,
    label: string.isRequired,
    dataTree: shape({}).isRequired,
    checked: arrayOf(string),
    isView: bool,
    localize: func,
    callBack: func,
    loaded: bool,
    disabled: bool,
  }

  static defaultProps = {
    checked: [],
    isView: false,
    loaded: true,
    disabled: false,
  }

  getAllChilds(data) {
    return data.map(x => (
      <TreeNode title={getNewName(x, true)} key={`${x.id}`}>
        {x.regionNodes && Object.keys(x.regionNodes).length > 0
          ? this.getAllChilds(x.regionNodes.map(transform))
          : null}
      </TreeNode>
    ))
  }

  getFilteredTree(node, ids) {
    if (ids.has(node.id)) return <TreeNode title={getNewName(node, true)} key={node.id} />

    const nodes = node.regionNodes.map(x => this.getFilteredTree(x, ids)).filter(x => x != null)
    if (nodes.length == 0) return null
    return (
      <TreeNode title={getNewName(node, true)} key={node.id}>
        {nodes}
      </TreeNode>
    )
  }

  render() {
    const {
      localize,
      name,
      label,
      checked,
      callBack,
      dataTree,
      isView,
      loaded,
      disabled,
    } = this.props

    return isView ? (
      <Tree>{this.getFilteredTree(dataTree, new Set(checked))}</Tree>
    ) : (
      <div>
        <label htmlFor={name}>{localize(label)}</label>
        <br />
        {loaded ? (
          <Tree checkedKeys={checked} disabled={disabled} onCheck={callBack} checkable>
            <TreeNode title={getNewName(dataTree, true)} key={`${dataTree.id}`}>
              {this.getAllChilds(dataTree.regionNodes.map(transform))}
            </TreeNode>
          </Tree>
        ) : (
          <Loader inline active size="small" />
        )}
      </div>
    )
  }
}

export default RegionTree

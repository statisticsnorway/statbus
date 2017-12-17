import React from 'react'
import { func, string, arrayOf, shape } from 'prop-types'
import Tree from 'antd/lib/tree'

const { TreeNode } = Tree

class RegionTree extends React.Component {
  static propTypes = {
    localize: func.isRequired,
    callBack: func.isRequired,
    name: string.isRequired,
    label: string.isRequired,
    dataTree: shape({}).isRequired,
    checked: arrayOf(string),
  }

  static defaultProps = {
    checked: [],
  }

  getChilds(data) {
    return data.map(x => (
      <TreeNode title={x.name} key={`${x.id}`}>
        {x.regionNodes && Object.keys(x.regionNodes).length > 0
          ? this.getChilds(x.regionNodes)
          : null}
      </TreeNode>
    ))
  }

  render() {
    const { localize, name, label, checked, callBack, dataTree } = this.props
    return (
      <div>
        <label htmlFor={name}>{localize(label)}</label>
        <Tree checkedKeys={checked} onCheck={callBack} checkable>
          <TreeNode title={dataTree.name} key={`${dataTree.id}`}>
            {this.getChilds(dataTree.regionNodes)}
          </TreeNode>
        </Tree>
      </div>
    )
  }
}

export default RegionTree

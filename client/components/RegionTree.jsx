import React, { Component } from 'react'
import PropTypes from 'prop-types'
import Tree from 'antd/lib/tree'

import { wrapper } from 'helpers/locale'

const TreeNode = Tree.TreeNode

const { func, string, arrayOf, shape } = PropTypes

class RegionTree extends Component {
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

  getChilds = data => data.map(x =>
     (<TreeNode title={x.name} key={`${x.id}`}>
       {(x.regionNodes && Object.keys(x.regionNodes).length > 0)
       ? this.getChilds(x.regionNodes)
       : null }
     </TreeNode>))

  render() {
    const { localize, name, label, checked, callBack, dataTree } = this.props
    const tree = (<TreeNode title={dataTree.name} key={`${dataTree.id}`}>{this.getChilds(dataTree.regionNodes)}</TreeNode>)

    return (
      <div>
        <label htmlFor={name}>{localize(label)}</label>
        <Tree
          checkable
          checkedKeys={checked}
          onCheck={callBack}
        >
          {tree}
        </Tree>
      </div>)
  }
}

export default wrapper(RegionTree)

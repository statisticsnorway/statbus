import React from 'react'
import { string, arrayOf, shape, bool } from 'prop-types'
import Tree from 'antd/lib/tree'

const { TreeNode } = Tree

class RegionTree extends React.Component {
  static propTypes = {
    name: string.isRequired,
    label: string.isRequired,
    dataTree: shape({}).isRequired,
    checked: arrayOf(string),
    isView: bool,
  }

  static defaultProps = {
    checked: [],
    isView: false,
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

  getPartedChilds(data) {
    const sumOfIds = [...this.props.checked]
    data.forEach(x =>
      x.regionNodes != null &&
        x.regionNodes.forEach(y => this.props.checked.includes(y.id) && sumOfIds.unshift(x.id)))
    return data.map(x =>
      sumOfIds.some(elem => elem === x.id) && (
          <TreeNode title={x.name} key={`${x.id}`}>
            {x.regionNodes && Object.keys(x.regionNodes).length > 0
              ? this.getPartedChilds(x.regionNodes.filter(y => sumOfIds.includes(y.id)))
              : null}
          </TreeNode>
      ))
  }

  render() {
    const { localize, name, label, checked, callBack, dataTree, isView } = this.props
    const checkAllRegions = dataTree.regionNodes.map(x => x.id).every(y => checked.includes(y))
    return isView ? (
      <Tree defaultExpandedKeys={['1']}>
        <TreeNode title={`${!checkAllRegions ? '' : dataTree.name}`} key={`${dataTree.id}`}>
          {!checkAllRegions && this.getPartedChilds(dataTree.regionNodes)}
        </TreeNode>
      </Tree>
    ) : (
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

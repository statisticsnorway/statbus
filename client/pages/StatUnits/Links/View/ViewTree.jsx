import React from 'react'
import { Tree } from 'antd'
import { Icon } from 'semantic-ui-react'

const TreeNode = Tree.TreeNode

const { array, func } = React.PropTypes

class ViewTree extends React.Component {
  static propTypes = {
    localize: func.isRequired,
    value: array.isRequired,
  }

  state = {
    data: this.props.value,
  }

  onLoadData = (node) => {
    const data = node.props.node
    if (data.children !== null) {
      return new Promise((resolve) => { resolve() })
    }
    return this.props.loadData(node.props.node)
  }

  render() {
    const { localize, loadData } = this.props
    const { data } = this.state
    console.log(data)
    const loop = nodes => nodes.map((item) => {
      return (
        <TreeNode title={item.name} key={`${item.id}-${item.type}`} node={item}>
          {item.children !== null && loop(item.children)}
        </TreeNode>
      )
    })

    return (
      <div>
        <Tree defaultExpandAll>
          {loop(this.props.value)}
        </Tree>
      </div>
    )
  }
}

export default ViewTree

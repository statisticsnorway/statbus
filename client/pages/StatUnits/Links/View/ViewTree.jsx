import React from 'react'
import { Tree } from 'antd'
import { Icon, Header } from 'semantic-ui-react'
import R from 'ramda'

import LinksGrid from '../Components/LinksGrid'

const TreeNode = Tree.TreeNode

const { array, func } = React.PropTypes

class ViewTree extends React.Component {
  static propTypes = {
    localize: func.isRequired,
    value: array.isRequired,
  }

  state = {
    tree: this.props.value,
    links: [],
  }

  shouldComponentUpdate(nextProps, nextState) {
    return this.props.localize.lang !== nextProps.localize.lang
      || !R.equals(this.props, nextProps)
      || !R.equals(this.state, nextState)
  }

  onLoadData = (node) => {
    const data = node.props.node
    if (data.children !== null) {
      return new Promise((resolve) => { resolve() })
    }
    return this.props.loadData(node.props.node)
  }

  onSelect = (keys, { selected, node }) => {
    this.setState({
      links: [],
    }, () => {
      const data = node.props.node
      if (selected) {
        this.props.loadData(data)
          .then(response => (
            this.setState({
              links: response.map(v => ({ source1: data, source2: v })),
            })
          ))
          .catch(e => console.log('error', e))
      }
    })
  }

  filterTreeNode = (node) => {
    const data = node.props.node
    return data.highlight
  }
  render() {
    const { localize, loadData, value } = this.props
    const { links } = this.state
    const loop = nodes => nodes.map((item) => {
      return (
        <TreeNode title={item.name} key={`${item.id}-${item.type}`} node={item}>
          {item.children !== null && loop(item.children)}
        </TreeNode>
      )
    })

    console.log('DATA', this.state, this.props.value)
    return (
      <div>
        {value.length !== 0 &&
          <div>
            <Header as="h4" dividing>{localize('LinksTree')}</Header>
            <Tree defaultExpandAll onSelect={this.onSelect} filterTreeNode={this.filterTreeNode}>
              {loop(value)}
            </Tree>
            <LinksGrid localize={localize} data={links} deleteLink={() => { alert('Not supported') }} />
          </div>
        }
      </div>
    )
  }
}

export default ViewTree

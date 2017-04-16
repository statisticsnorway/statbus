import React from 'react'
import { Tree } from 'antd'
import { Segment, Icon, Header } from 'semantic-ui-react'
import R from 'ramda'

import statUnitIcons from 'helpers/statUnitIcons'
import statUnitTypes from 'helpers/statUnitTypes'
import LinksGrid from '../Components/LinksGrid'

const TreeNode = Tree.TreeNode

const { array, func, string, number } = React.PropTypes

const UnitNode = ({ localize, code, name, type }) => (
  <div>
    <Icon name={statUnitIcons(type)} title={localize(statUnitTypes.get(type))} />
    <strong>{code}</strong>: {name}
  </div>
)

UnitNode.propTypes = {
  localize: func.isRequired,
  code: string.isRequired,
  name: string.isRequired,
  type: number.isRequired,
}

class ViewTree extends React.Component {
  static propTypes = {
    localize: func.isRequired,
    value: array.isRequired,
    loadData: func.isRequired,
  }

  state = {
    tree: this.props.value,
    selectedKeys: [],
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
      selectedKeys: keys,
      links: [],
    }, () => {
      const data = node.props.node
      if (selected) {
        this.props.loadData(data)
          .then(response => (
            this.setState({
              selectedKeys: keys,
              links: response,
            })
          ))
          .catch(() => {
            this.setState({ selectedKeys: [] })
          })
      }
    })
  }

  filterTreeNode = (node) => {
    const data = node.props.node
    return data.highlight
  }
  render() {
    const { localize, value } = this.props
    const { links, selectedKeys } = this.state
    const loop = nodes => nodes.map(item => (
      <TreeNode title={<UnitNode localize={localize} {...item} />} key={`${item.id}-${item.type}`} node={item}>
        {item.children !== null && loop(item.children)}
      </TreeNode>
    ))
    return (
      <div>
        {value.length !== 0 &&
          <Segment>
            <Header as="h4" dividing>{localize('SearchResults')}</Header>
            <Tree
              defaultExpandAll
              selectedKeys={selectedKeys}
              onSelect={this.onSelect}
              filterTreeNode={this.filterTreeNode}
            >
              {loop(value)}
            </Tree>
            <LinksGrid localize={localize} data={links} readOnly />
          </Segment>
        }
      </div>
    )
  }
}

export default ViewTree

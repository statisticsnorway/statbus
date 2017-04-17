import React from 'react'
import { Tree } from 'antd'
import { Segment, Icon, Header } from 'semantic-ui-react'
import R from 'ramda'

import { wrapper } from 'helpers/locale'
import ViewFilter from './ViewFilter'
import statUnitIcons from 'helpers/statUnitIcons'
import statUnitTypes from 'helpers/statUnitTypes'
import LinksGrid from '../Components/LinksGrid'

const TreeNode = Tree.TreeNode

const { func, string, number, object } = React.PropTypes

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


class ViewLinks extends React.Component {
  static propTypes = {
    localize: func.isRequired,
    findUnit: func.isRequired,
    filter: object,
    getUnitChildren: func.isRequired,
  }

  static defaultProps = {
    filter: undefined,
  }

  state = {
    tree: [],
    selectedKeys: [],
    links: [],
    isLoading: undefined,
  }

  componentDidMount() {
    const { filter } = this.props
    if (filter) this.searchUnit(filter)
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
    return this.props.getUnitChildren(node.props.node)
  }

  onSelect = (keys, { selected, node }) => {
    this.setState({
      selectedKeys: keys,
      links: [],
    }, () => {
      const data = node.props.node
      if (selected) {
        this.props.getUnitChildren(data)
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

  searchUnit = (filter) => {
    const { findUnit } = this.props
    this.setState({
      isLoading: true,
    }, () => {
      findUnit(filter)
        .then((resp) => {
          this.setState({ isLoading: false, tree: resp, selectedKeys: [], links: [] })
        })
        .catch(() => {
          this.setState({ isLoading: false, tree: [], selectedKeys: [], links: [] })
        })
    })
  }

  filterTreeNode = (node) => {
    const data = node.props.node
    return data.highlight
  }
  render() {
    const { localize, filter } = this.props
    const { tree, links, selectedKeys, isLoading } = this.state
    const loop = nodes => nodes.map(item => (
      <TreeNode title={<UnitNode localize={localize} {...item} />} key={`${item.id}-${item.type}`} node={item}>
        {item.children !== null && loop(item.children)}
      </TreeNode>
    ))
    return (
      <div>
        <ViewFilter
          isLoading={isLoading}
          value={filter}
          localize={localize}
          onFilter={this.searchUnit}
        />
        <br />
        {isLoading === false &&
          <Segment>
            <Header as="h4" dividing>{localize('SearchResults')}</Header>
            {tree.length !== 0 &&
              <Tree
                defaultExpandAll
                selectedKeys={selectedKeys}
                onSelect={this.onSelect}
                filterTreeNode={this.filterTreeNode}
              >
                {loop(tree)}
              </Tree>
            }
            <LinksGrid localize={localize} data={links} readOnly />
          </Segment>
        }
      </div>
    )
  }
}

export default wrapper(ViewLinks)

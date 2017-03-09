import React from 'react'
import { Menu } from 'semantic-ui-react'
import { Link } from 'react-router'
import R from 'ramda'

import styles from './styles'

const { func, node, number } = React.PropTypes

class Paginate extends React.Component {

  static propTypes = {
    totalPages: number,
    onChange: func.isRequired,
    children: node.isRequired,
  }

  static defaultProps = {
    query: {
      page: 1,
      pageSize: 15,
    },
    totalPages: 1,
    queryString: '',
  }

  constructor(props, context) {
    super(props, context)
    this.state = {
      page: context.location.query.page,
      pageSize: context.location.query.pageSize,
    }
  }

  componentWillReceiveProps(nextProps, nextContext) {
    const pick = R.pickAll('page', 'pageSize')
    const prevPg = pick()
    if ()
  }

  handleChange = (name, value) => () => {
    this.props.onChange({ name, value })
  }

  renderPageSizeLink = (value) => {
    const { queryString, page, pageSize } = this.state
    const pathname = queryString.includes(`pageSize=${pageSize}`)
      ? R.replace(`pageSize=${pageSize}`, `pageSize=${value}`, queryString)
      : `${queryString}&pageSize=${value}`

    const isCurrent = value === pageSize
    const link = isCurrent
      ? <b>{value}</b>
      : <Link to={pathname}>{value}</Link>

    return (
      <Menu.Item
        key={value}
        onClick={this.handleChange('pageSize', value)}
        content={value}
        disabled={isCurrent}
        as={() => link}
      />
    )
  }

  renderPageLink = (value) => {
    const { queryString, page, pageSize } = this.state
    const pathname = queryString.includes(`page=${page}`)
      ? R.replace(`page=${page}`, `page=${value}`, queryString)
      : `${queryString}&page=${value}`

    const isCurrent = value === page
    const link = isCurrent
      ? <b>{value}</b>
      : <Link to={pathname}>{value}</Link>

    return (
      <Menu.Item
        key={value}
        onClick={this.handleChange('page', value)}
        content={value}
        disabled={isCurrent}
        as={() => link}
      />
    )
  }

  render() {
    const { totalPages, children } = this.props

    const pageSizeLinks =
      [5, 10, 15, 25, 50].map(this.renderPageSizeLink)
    const pageLinks =
      R.range(1, totalPages).map(this.renderPageLink)

    return (
      <div className={styles.root}>
        <Menu floated="right" pagination>
          {pageSizeLinks}
        </Menu>
        {children}
        <Menu floated="center" pagination>
          {pageLinks}
        </Menu>
      </div>
    )
  }
}

export default Paginate

import React from 'react'
import { Menu } from 'semantic-ui-react'
import { Link } from 'react-router'
import R from 'ramda'

import { wrapper } from 'helpers/locale'
import { getPagesRange, getPageSizesRange } from './utils'
import styles from './styles'

const { node, number, func, oneOfType, shape, string } = React.PropTypes
class Paginate extends React.Component {

  static propTypes = {
    routing: shape({
      pathname: string,
      page: oneOfType([number, string]),
      pageSize: oneOfType([number, string]),
      queryString: string,
    }).isRequired,
    totalCount: oneOfType([number, string]),
    children: node.isRequired,
    localize: func.isRequired,
  }

  static defaultProps = {
    totalCount: 0,
  }

  getPage = () => Number(this.props.routing.page) || 1
  getPageSize = () => Number(this.props.routing.pageSize)
  getTotalCount = () => Number(this.props.totalCount)
  getTotalPages = () => Math.ceil(this.getTotalCount() / this.getPageSize())

  getDisplayTotalString() {
    const { localize } = this.props
    const to = this.getPage() * this.getPageSize()
    // eslint-disable-next-line no-mixed-operators
    const from = to - this.getPageSize() + 1
    const rangeDescription = this.getTotalPages() === 1
      ? localize('AllOf')
      : from !== to
        ? `${from} - ${to} ${localize('OfCount')}`
        : `№ ${from} ${localize('OfCount')}`

    return `${localize('Displaying')} ${rangeDescription} ${this.getTotalCount()}`
  }

  renderPageSizeLink = (value) => {
    const { pathname, queryString } = this.props.routing
    const current = this.getPageSize()

    const nextQueryString = queryString.includes(`pageSize=${current}`)
      ? R.replace(`pageSize=${current}`, `pageSize=${value}`, queryString)
      : queryString
        ? `${queryString}&pageSize=${value}`
        : `?pageSize=${value}`

    const isCurrent = value === current
    const link = () => isCurrent
      ? <b className="active item">{value}</b>
      : <Link to={`${pathname}${nextQueryString}`} className="item">{value}</Link>

    return <Menu.Item key={value} content={value} disabled={isCurrent} as={link} />
  }

  renderPageLink = (value) => {
    if (!R.is(Number, value)) return <Menu.Item content={value} disabled />

    const { pathname, queryString } = this.props.routing
    const current = this.getPage()

    const nextQueryString = queryString.includes(`page=${current}`)
      ? R.replace(`page=${current}`, `page=${value}`, queryString)
      : queryString
        ? `${queryString}&page=${value}`
        : `?page=${value}`

    const isCurrent = value === current
    const link = () => isCurrent
      ? <b className="active item">{value}</b>
      : <Link to={`${pathname}${nextQueryString}`} className="item">{value}</Link>

    return <Menu.Item key={value} content={value} disabled={isCurrent} as={link} />
  }

  render() {
    const pageSizeLinks = getPageSizesRange(this.getPageSize()).map(this.renderPageSizeLink)
    const pageLinks = getPagesRange(this.getPage(), this.getTotalPages()).map(this.renderPageLink)
    return (
      <div className={styles.root}>
        <Menu pagination>
          <span className={styles.totalCount}>
            {this.getDisplayTotalString()}
          </span>
          <span>
            {this.props.localize('PageSize')}:
          </span>
          {pageSizeLinks}
        </Menu>
        {this.props.children}
        <Menu pagination>
          <span>{this.props.localize('PageNum')}:</span>
          {pageLinks}
        </Menu>
      </div>
    )
  }
}

export default wrapper(Paginate)
